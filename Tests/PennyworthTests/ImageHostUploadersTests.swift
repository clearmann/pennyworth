@testable import Pennyworth
import CryptoKit
import XCTest

final class ImageHostUploadersTests: XCTestCase {
    private let fixedDate = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14T22:13:20Z

    func testS3PathStyleSigV4RequestAndURL() throws {
        let uploader = S3CompatibleUploader()
        let payload = UploadPayload(
            data: Data("hello s3".utf8),
            originalFilename: "demo.png",
            fileExtension: "png",
            mimeType: "image/png",
            objectKey: "uPic/2023/demo.png"
        )
        let config = ImageHostConfig(
            id: "r2",
            name: "R2",
            provider: .s3,
            bucket: "my-bucket",
            region: "auto",
            endpoint: "https://acct.r2.cloudflarestorage.com",
            accessKey: "AKIAEXAMPLE",
            domain: "https://img.example.com",
            suffix: "?w=800",
            usePathStyle: true
        )

        let prepared = try uploader.buildRequest(payload: payload, config: config, secretKey: "SECRETKEY123", date: fixedDate)
        XCTAssertEqual(prepared.request.httpMethod, "PUT")
        XCTAssertEqual(prepared.request.url?.absoluteString, "https://acct.r2.cloudflarestorage.com/my-bucket/uPic/2023/demo.png")
        XCTAssertEqual(prepared.request.value(forHTTPHeaderField: "Host"), "acct.r2.cloudflarestorage.com")
        XCTAssertEqual(prepared.request.value(forHTTPHeaderField: "x-amz-date"), "20231114T221320Z")

        let expectedPayloadHash = UploadResponseHelper.hexString(SHA256.hash(data: payload.data))
        XCTAssertEqual(prepared.request.value(forHTTPHeaderField: "x-amz-content-sha256"), expectedPayloadHash)

        // Independently verify AWS SigV4 signature
        let canonicalRequest = """
        PUT
        /my-bucket/uPic/2023/demo.png

        content-type:image/png
        host:acct.r2.cloudflarestorage.com
        x-amz-content-sha256:\(expectedPayloadHash)
        x-amz-date:20231114T221320Z

        content-type;host;x-amz-content-sha256;x-amz-date
        \(expectedPayloadHash)
        """
        let canonicalHash = UploadResponseHelper.hexString(SHA256.hash(data: Data(canonicalRequest.utf8)))
        let stringToSign = "AWS4-HMAC-SHA256\n20231114T221320Z\n20231114/auto/s3/aws4_request\n\(canonicalHash)"
        let kDate = HMAC<SHA256>.authenticationCode(for: Data("20231114".utf8), using: SymmetricKey(data: Data("AWS4SECRETKEY123".utf8)))
        let kRegion = HMAC<SHA256>.authenticationCode(for: Data("auto".utf8), using: SymmetricKey(data: Data(kDate)))
        let kService = HMAC<SHA256>.authenticationCode(for: Data("s3".utf8), using: SymmetricKey(data: Data(kRegion)))
        let kSigning = HMAC<SHA256>.authenticationCode(for: Data("aws4_request".utf8), using: SymmetricKey(data: Data(kService)))
        let expectedSig = UploadResponseHelper.hexString(HMAC<SHA256>.authenticationCode(for: Data(stringToSign.utf8), using: SymmetricKey(data: Data(kSigning))))

        XCTAssertEqual(
            prepared.request.value(forHTTPHeaderField: "Authorization"),
            "AWS4-HMAC-SHA256 Credential=AKIAEXAMPLE/20231114/auto/s3/aws4_request, SignedHeaders=content-type;host;x-amz-content-sha256;x-amz-date, Signature=\(expectedSig)"
        )

        let okResponse = HTTPURLResponse(url: prepared.request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        let url = try uploader.parseResponse(data: Data(), response: okResponse, prepared: prepared, config: config, encodeURL: true)
        XCTAssertEqual(url, "https://img.example.com/uPic/2023/demo.png?w=800")

        let errResponse = HTTPURLResponse(url: prepared.request.url!, statusCode: 403, httpVersion: nil, headerFields: nil)!
        let errXML = Data("<Error><Code>AccessDenied</Code><Message>Access Denied</Message></Error>".utf8)
        XCTAssertThrowsError(try uploader.parseResponse(data: errXML, response: errResponse, prepared: prepared, config: config, encodeURL: true)) { error in
            XCTAssertEqual(error as? ImageUploadError, .serverError(statusCode: 403, message: "Access Denied"))
        }
    }

    func testS3VirtualHostedStyleWithoutCustomEndpoint() throws {
        let uploader = S3CompatibleUploader()
        let payload = UploadPayload(
            data: Data("abc".utf8),
            originalFilename: "a.txt",
            fileExtension: "txt",
            mimeType: "text/plain",
            objectKey: "dir/a.txt"
        )
        let config = ImageHostConfig(
            id: "aws",
            name: "AWS",
            provider: .s3,
            bucket: "photos",
            region: "us-west-2",
            endpoint: "",
            accessKey: "AK",
            domain: "",
            usePathStyle: false
        )
        let prepared = try uploader.buildRequest(payload: payload, config: config, secretKey: "SK", date: fixedDate)
        XCTAssertEqual(prepared.request.url?.absoluteString, "https://photos.s3.us-west-2.amazonaws.com/dir/a.txt")
        let ok = HTTPURLResponse(url: prepared.request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        let publicURL = try uploader.parseResponse(data: Data(), response: ok, prepared: prepared, config: config, encodeURL: true)
        XCTAssertEqual(publicURL, "https://photos.s3.us-west-2.amazonaws.com/dir/a.txt")
    }

    func testAliyunOSSSignatureAndRegionNormalization() throws {
        let uploader = AliyunOSSUploader()
        let payload = UploadPayload(
            data: Data("hello oss".utf8),
            originalFilename: "pic.png",
            fileExtension: "png",
            mimeType: "image/png",
            objectKey: "uPic/pic.png"
        )
        let config = ImageHostConfig(
            id: "oss",
            name: "Aliyun",
            provider: .aliyunOSS,
            bucket: "blog-bucket",
            region: "cn-hangzhou", // should normalize to oss-cn-hangzhou.aliyuncs.com
            accessKey: "LTAI123",
            domain: ""
        )

        let prepared = try uploader.buildRequest(payload: payload, config: config, secretKey: "OSS_SECRET", date: fixedDate)
        XCTAssertEqual(prepared.request.httpMethod, "PUT")
        XCTAssertEqual(prepared.request.url?.absoluteString, "https://blog-bucket.oss-cn-hangzhou.aliyuncs.com/uPic/pic.png")
        XCTAssertEqual(prepared.request.value(forHTTPHeaderField: "Date"), "Tue, 14 Nov 2023 22:13:20 GMT")

        let expectedMD5 = Data(Insecure.MD5.hash(data: payload.data)).base64EncodedString()
        XCTAssertEqual(prepared.request.value(forHTTPHeaderField: "Content-MD5"), expectedMD5)

        let stringToSign = "PUT\n\(expectedMD5)\nimage/png\nTue, 14 Nov 2023 22:13:20 GMT\n/blog-bucket/uPic/pic.png"
        let mac = HMAC<Insecure.SHA1>.authenticationCode(for: Data(stringToSign.utf8), using: SymmetricKey(data: Data("OSS_SECRET".utf8)))
        let expectedAuth = "OSS LTAI123:\(Data(mac).base64EncodedString())"
        XCTAssertEqual(prepared.request.value(forHTTPHeaderField: "Authorization"), expectedAuth)

        let ok = HTTPURLResponse(url: prepared.request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        let url = try uploader.parseResponse(data: Data(), response: ok, prepared: prepared, config: config, encodeURL: true)
        XCTAssertEqual(url, "https://blog-bucket.oss-cn-hangzhou.aliyuncs.com/uPic/pic.png")
    }

    func testTencentCOSSignatureAndURL() throws {
        let uploader = TencentCOSUploader()
        let payload = UploadPayload(
            data: Data("hello cos".utf8),
            originalFilename: "cat.jpg",
            fileExtension: "jpg",
            mimeType: "image/jpeg",
            objectKey: "images/cat.jpg"
        )
        let config = ImageHostConfig(
            id: "cos",
            name: "Tencent COS",
            provider: .tencentCOS,
            bucket: "demo-1250000000",
            region: "ap-guangzhou",
            accessKey: "AKID_TEST",
            domain: "https://static.example.com"
        )

        let prepared = try uploader.buildRequest(payload: payload, config: config, secretKey: "COS_SECRET", date: fixedDate)
        XCTAssertEqual(prepared.request.httpMethod, "PUT")
        XCTAssertEqual(prepared.request.url?.absoluteString, "https://demo-1250000000.cos.ap-guangzhou.myqcloud.com/images/cat.jpg")

        let keyTime = "1700000000;1700003600"
        let signKey = UploadResponseHelper.hexString(
            HMAC<Insecure.SHA1>.authenticationCode(for: Data(keyTime.utf8), using: SymmetricKey(data: Data("COS_SECRET".utf8)))
        )
        let httpString = "put\n/images/cat.jpg\n\nhost=demo-1250000000.cos.ap-guangzhou.myqcloud.com\n"
        let sha1Http = UploadResponseHelper.hexString(Insecure.SHA1.hash(data: Data(httpString.utf8)))
        let stringToSign = "sha1\n\(keyTime)\n\(sha1Http)\n"
        let expectedSig = UploadResponseHelper.hexString(
            HMAC<Insecure.SHA1>.authenticationCode(for: Data(stringToSign.utf8), using: SymmetricKey(data: Data(signKey.utf8)))
        )
        let expectedAuth = "q-sign-algorithm=sha1&q-ak=AKID_TEST&q-sign-time=\(keyTime)&q-key-time=\(keyTime)&q-header-list=host&q-url-param-list=&q-signature=\(expectedSig)"
        XCTAssertEqual(prepared.request.value(forHTTPHeaderField: "Authorization"), expectedAuth)

        let ok = HTTPURLResponse(url: prepared.request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        let url = try uploader.parseResponse(data: Data(), response: ok, prepared: prepared, config: config, encodeURL: true)
        XCTAssertEqual(url, "https://static.example.com/images/cat.jpg")
    }

    func testQiniuUploadTokenMultipartAndResponseParsing() throws {
        let uploader = QiniuUploader()
        let payload = UploadPayload(
            data: Data("hello qiniu".utf8),
            originalFilename: "note.png",
            fileExtension: "png",
            mimeType: "image/png",
            objectKey: "uPic/note.png"
        )
        let config = ImageHostConfig(
            id: "qn",
            name: "Qiniu",
            provider: .qiniu,
            bucket: "my-space",
            region: QiniuRegion.z2.rawValue,
            accessKey: "QN_AK",
            domain: "https://cdn.qiniu.example.com",
            suffix: "-slim"
        )

        let prepared = try uploader.buildRequest(payload: payload, config: config, secretKey: "QN_SK", date: fixedDate)
        XCTAssertEqual(prepared.request.httpMethod, "POST")
        XCTAssertEqual(prepared.request.url?.absoluteString, "https://upload-z2.qiniup.com")
        let contentType = try XCTUnwrap(prepared.request.value(forHTTPHeaderField: "Content-Type"))
        XCTAssertTrue(contentType.hasPrefix("multipart/form-data; boundary="))

        let expectedToken = try QiniuUploader.makeUploadToken(
            accessKey: "QN_AK",
            secretKey: "QN_SK",
            bucket: "my-space",
            objectKey: "uPic/note.png",
            deadline: 1_700_003_600
        )
        let parts = expectedToken.split(separator: ":")
        XCTAssertEqual(parts.count, 3)
        XCTAssertEqual(parts[0], "QN_AK")

        let bodyString = try XCTUnwrap(String(data: prepared.request.httpBody ?? Data(), encoding: .utf8))
        XCTAssertTrue(bodyString.contains("name=\"token\"\r\n\r\n\(expectedToken)"))
        XCTAssertTrue(bodyString.contains("name=\"key\"\r\n\r\nuPic/note.png"))
        XCTAssertTrue(bodyString.contains("name=\"file\"; filename=\"note.png\""))
        XCTAssertTrue(bodyString.contains("hello qiniu"))

        let ok = HTTPURLResponse(url: prepared.request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        let okJSON = Data("{\"hash\":\"Fh8x\",\"key\":\"uPic/note.png\"}".utf8)
        let url = try uploader.parseResponse(data: okJSON, response: ok, prepared: prepared, config: config, encodeURL: true)
        XCTAssertEqual(url, "https://cdn.qiniu.example.com/uPic/note.png-slim")

        let err = HTTPURLResponse(url: prepared.request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
        let errJSON = Data("{\"error\":\"bad token\"}".utf8)
        XCTAssertThrowsError(try uploader.parseResponse(data: errJSON, response: err, prepared: prepared, config: config, encodeURL: true)) { error in
            XCTAssertEqual(error as? ImageUploadError, .serverError(statusCode: 401, message: "bad token"))
        }
    }
}
