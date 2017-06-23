//
//  MonkeyKing.swift
//  MonkeyKing
//
//  Created by NIX on 15/9/11.
//  Copyright © 2015年 nixWork. All rights reserved.
//

import UIKit
import WebKit

open class MonkeyKing: NSObject {

    public enum DeliverResult {
        case success(ResponseJSON?)
        case failure(Error)
    }
    public typealias ResponseJSON = [String: Any]
    public typealias DeliverCompletionHandler = (_ result: DeliverResult) -> Void
    public typealias OAuthCompletionHandler = (_ info: [String: Any]?, _ response: URLResponse?, _ error: Swift.Error?) -> Void
    public typealias PayCompletionHandler = (_ result: Bool) -> Void

    fileprivate static let sharedMonkeyKing = MonkeyKing()

    fileprivate var accountSet = Set<Account>()

    fileprivate var deliverCompletionHandler: DeliverCompletionHandler?
    fileprivate var oauthCompletionHandler: OAuthCompletionHandler?
    fileprivate var payCompletionHandler: PayCompletionHandler?
    fileprivate var customAlipayOrderScheme: String?

    fileprivate var webView: WKWebView?

    fileprivate override init() {}

    public enum Account: Hashable {
        case weChat(appID: String, appKey: String?)
        case qq(appID: String)
        case weibo(appID: String, appKey: String, redirectURL: String)
        case pocket(appID: String)
        case alipay(appID: String)
        case twitter(appID: String, appKey: String, redirectURL: String)

        public var isAppInstalled: Bool {
            switch self {
            case .weChat:
                return MonkeyKing.isAppInstalled(app: .weChat)
            case .qq:
                return MonkeyKing.isAppInstalled(app: .qq)
            case .weibo:
                return MonkeyKing.isAppInstalled(app: .weibo)
            case .pocket:
                return MonkeyKing.isAppInstalled(app: .pocket)
            case .alipay:
                return MonkeyKing.isAppInstalled(app: .alipay)
            case .twitter:
                return MonkeyKing.isAppInstalled(app: .twitter)
            }
        }

        public var appID: String {
            switch self {
            case .weChat(let appID, _):
                return appID
            case .qq(let appID):
                return appID
            case .weibo(let appID, _, _):
                return appID
            case .pocket(let appID):
                return appID
            case .alipay(let appID):
                return appID
            case .twitter(let appID, _, _):
                return appID
            }
        }

        public var hashValue: Int {
            return appID.hashValue
        }

        public var canWebOAuth: Bool {
            switch self {
            case .qq, .weibo, .pocket, .weChat, .twitter:
                return true
            default:
                return false
            }
        }

        public static func ==(lhs: MonkeyKing.Account, rhs: MonkeyKing.Account) -> Bool {
            return lhs.appID == rhs.appID
        }
    }

    public enum SupportedPlatform {
        case qq
        case weChat
        case weibo
        case pocket(requestToken: String)
        case alipay
        case twitter
    }

    open class func registerAccount(_ account: Account) {
        guard account.isAppInstalled || account.canWebOAuth else { return }
        for oldAccount in MonkeyKing.sharedMonkeyKing.accountSet {
            switch oldAccount {
            case .weChat:
                if case .weChat = account { sharedMonkeyKing.accountSet.remove(oldAccount) }
            case .qq:
                if case .qq = account { sharedMonkeyKing.accountSet.remove(oldAccount) }
            case .weibo:
                if case .weibo = account { sharedMonkeyKing.accountSet.remove(oldAccount) }
            case .pocket:
                if case .pocket = account { sharedMonkeyKing.accountSet.remove(oldAccount) }
            case .alipay:
                if case .alipay = account { sharedMonkeyKing.accountSet.remove(oldAccount) }
            case .twitter:
                if case .twitter = account { sharedMonkeyKing.accountSet.remove(oldAccount) }
            }
        }
        sharedMonkeyKing.accountSet.insert(account)
    }
}


// MARK: Check If App Installed

extension MonkeyKing {

    public enum App {
        case weChat
        case qq
        case weibo
        case pocket
        case alipay
        case twitter
    }

    public class func isAppInstalled(app: App) -> Bool {
        switch app {
        case .weChat:
            return sharedMonkeyKing.canOpenURL(urlString: "weixin://")
        case .qq:
            return sharedMonkeyKing.canOpenURL(urlString: "mqqapi://")
        case .weibo:
            return sharedMonkeyKing.canOpenURL(urlString: "weibosdk://request")
        case .pocket:
            return sharedMonkeyKing.canOpenURL(urlString: "pocket-oauth-v1://")
        case .alipay:
            return sharedMonkeyKing.canOpenURL(urlString: "alipayshare://")
        case .twitter:
            return sharedMonkeyKing.canOpenURL(urlString: "twitter://")
        }
    }
}


// MARK: OpenURL Handler

extension MonkeyKing {

    public class func handleOpenURL(_ url: URL) -> Bool {
        guard let urlScheme = url.scheme else { return false }
        // WeChat
        if urlScheme.hasPrefix("wx") {
            let urlString = url.absoluteString
            // OAuth
            if urlString.contains("state=Weixinauth") {
                let queryDictionary = url.monkeyking_queryDictionary
                guard let code = queryDictionary["code"] as? String else { return false }
                // Login Succcess
                fetchWeChatOAuthInfoByCode(code: code) { (info, response, error) in
                    sharedMonkeyKing.oauthCompletionHandler?(info, response, error)
                }
                return true
            }
            // SMS OAuth
            if urlString.contains("wapoauth") {
                let queryDictionary = url.monkeyking_queryDictionary
                guard let m = queryDictionary["m"] as? String else { return false }
                guard let t = queryDictionary["t"] as? String else { return false }
                guard let account = sharedMonkeyKing.accountSet[.weChat] else { return false }
                let appID = account.appID
                let urlString = "https://open.weixin.qq.com/connect/smsauthorize?appid=\(appID)&redirect_uri=\(appID)%3A%2F%2Foauth&response_type=code&scope=snsapi_message,snsapi_userinfo,snsapi_friend,snsapi_contact&state=xxx&uid=1926559385&m=\(m)&t=\(t)"
                addWebView(withURLString: urlString)
                return true
            }
            // Pay
            if urlString.contains("://pay/") {
                var result = false
                defer {
                    sharedMonkeyKing.payCompletionHandler?(result)
                }
                let queryDictionary = url.monkeyking_queryDictionary
                guard let ret = queryDictionary["ret"] as? String else { return false }
                result = (ret == "0")
                return result
            }
            // Share
            if let data = UIPasteboard.general.data(forPasteboardType: "content") {
                if let dict = try? PropertyListSerialization.propertyList(from: data, options: PropertyListSerialization.MutabilityOptions(), format: nil) as? [String: Any] {
                    guard
                        let account = sharedMonkeyKing.accountSet[.weChat],
                        let info = dict?[account.appID] as? [String: Any],
                        let result = info["result"] as? String,
                        let resultCode = Int(result) else {
                            return false
                    }
                    let success = (resultCode == 0)
                    if success {
                        sharedMonkeyKing.deliverCompletionHandler?(.success(nil))
                    } else {
                        sharedMonkeyKing.deliverCompletionHandler?(.failure(.sdk(reason: .unknown))) // TODO: pass resultCode
                    }
                    return success
                }
            }
            // OAuth Failed
            if urlString.contains("platformId=wechat") && !urlString.contains("state=Weixinauth") {
                let error = NSError(domain: "WeChat OAuth Error", code: -1, userInfo: nil)
                sharedMonkeyKing.oauthCompletionHandler?(nil, nil, error)
                return false
            }
            return false
        }
        // QQ Share
        if urlScheme.hasPrefix("QQ") {
            guard let errorDescription = url.monkeyking_queryDictionary["error"] as? String else { return false }
            let success = (errorDescription == "0")
            if success {
                sharedMonkeyKing.deliverCompletionHandler?(.success(nil))
            } else {
                sharedMonkeyKing.deliverCompletionHandler?(.failure(.sdk(reason: .unknown))) // TODO: pass errorDescription
            }
            return success
        }
        // QQ OAuth
        if urlScheme.hasPrefix("tencent") {
            guard let account = sharedMonkeyKing.accountSet[.qq] else { return false }
            var userInfo: [String: Any]?
            var error: Swift.Error?
            defer {
                sharedMonkeyKing.oauthCompletionHandler?(userInfo, nil, error)
            }
            guard
                let data = UIPasteboard.general.data(forPasteboardType: "com.tencent.tencent\(account.appID)"),
                let info = NSKeyedUnarchiver.unarchiveObject(with: data) as? [String: Any] else {
                    error = NSError(domain: "OAuth Error", code: -1, userInfo: nil)
                    return false
            }
            guard let result = info["ret"] as? Int, result == 0 else {
                if let errorDomatin = info["user_cancelled"] as? String, errorDomatin == "YES" {
                    error = NSError(domain: "User Cancelled", code: -2, userInfo: nil)
                } else {
                    error = NSError(domain: "OAuth Error", code: -1, userInfo: nil)
                }
                return false
            }
            userInfo = info
            return true
        }
        // Weibo
        if urlScheme.hasPrefix("wb") {
            let items = UIPasteboard.general.items
            var results = [String: Any]()
            for item in items {
                for (key, value) in item {
                    if let valueData = value as? Data, key == "transferObject" {
                        results[key] = NSKeyedUnarchiver.unarchiveObject(with: valueData)
                    }
                }
            }
            guard
                let responseInfo = results["transferObject"] as? [String: Any],
                let type = responseInfo["__class"] as? String else {
                    return false
            }
            guard let statusCode = responseInfo["statusCode"] as? Int else {
                return false
            }
            switch type {
            // OAuth
            case "WBAuthorizeResponse":
                var userInfo: [String: Any]?
                var error: Swift.Error?
                defer {
                    sharedMonkeyKing.oauthCompletionHandler?(responseInfo, nil, error)
                }
                userInfo = responseInfo
                if statusCode != 0 {
                    error = NSError(domain: "OAuth Error", code: -1, userInfo: userInfo)
                    return false
                }
                return true
            // Share
            case "WBSendMessageToWeiboResponse":
                let success = (statusCode == 0)
                if success {
                    sharedMonkeyKing.deliverCompletionHandler?(.success(nil))
                } else {
                    sharedMonkeyKing.deliverCompletionHandler?(.failure(.sdk(reason: .unknown)))
                }
                return success
            default:
                break
            }
        }
        // Pocket OAuth
        if urlScheme.hasPrefix("pocketapp") {
            sharedMonkeyKing.oauthCompletionHandler?(nil, nil, nil)
            return true
        }
        // Alipay
        var canHandleAlipay = false
        if let customScheme = sharedMonkeyKing.customAlipayOrderScheme {
            if urlScheme == customScheme { canHandleAlipay = true }
        } else if urlScheme.hasPrefix("ap") {
            canHandleAlipay = true
        }
        if canHandleAlipay {
            let urlString = url.absoluteString
            if urlString.contains("//safepay/?") {
                var result = false
                defer {
                    sharedMonkeyKing.payCompletionHandler?(result)
                }
                guard
                    let query = url.query,
                    let response = query.monkeyking_urlDecodedString?.data(using: .utf8),
                    let json = response.monkeyking_json,
                    let memo = json["memo"] as? [String: Any],
                    let status = memo["ResultStatus"] as? String else {
                        return false
                }
                result = (status == "9000")
                return result
            } else {
                // Share
                guard
                    let account = sharedMonkeyKing.accountSet[.alipay] ,
                    let data = UIPasteboard.general.data(forPasteboardType: "com.alipay.openapi.pb.resp.\(account.appID)"),
                    let dict = try? PropertyListSerialization.propertyList(from: data, options: PropertyListSerialization.MutabilityOptions(), format: nil) as? [String: Any],
                    let objects = dict?["$objects"] as? NSArray,
                    let result = objects[12] as? Int else {
                        return false
                }
                let success = (result == 0)
                if success {
                    sharedMonkeyKing.deliverCompletionHandler?(.success(nil))
                } else {
                    sharedMonkeyKing.deliverCompletionHandler?(.failure(.sdk(reason: .unknown)))
                }
                return success
            }
        }
        return false
    }
}

// MARK: Share Message

extension MonkeyKing {

    public enum Media {
        case url(URL)
        case image(UIImage)
        case audio(audioURL: URL, linkURL: URL?)
        case video(URL)
        case file(Data)
    }

    public typealias Info = (title: String?, description: String?, thumbnail: UIImage?, media: Media?)

    public enum Message {

        public enum WeChatSubtype {
            case session(info: Info)
            case timeline(info: Info)
            case favorite(info: Info)

            var scene: String {
//                switch self {
//                case .session:
//                    return "0"
//                case .timeline:
//                    return "1"
//                case .favorite:
//                    return "2"
//                }
                switch self {
                case .session(info: (title: _, description: _, thumbnail: _, media: _)):
                    return "0"
                case .timeline(info: (title: _, description: _, thumbnail: _, media: _)):
                    return "1"
                case .favorite(info: (title: _, description: _, thumbnail: _, media: _)):
                    return "2"
                }
            }

            var info: Info {
                switch self {
                case .session(let info):
                    return info
                case .timeline(let info):
                    return info
                case .favorite(let info):
                    return info
                }
            }
        }
        case weChat(WeChatSubtype)

        public enum QQSubtype {
            case friends(info: Info)
            case zone(info: Info)
            case favorites(info: Info)
            case dataline(info: Info)

            var scene: Int {
                switch self {
                case .friends(info: (title: _, description: _, thumbnail: _, media: _)):
                    return 0x00
                case .zone(info: (title: _, description: _, thumbnail: _, media: _)):
                    return 0x01
                case .favorites(info: (title: _, description: _, thumbnail: _, media: _)):
                    return 0x08
                case .dataline(info: (title: _, description: _, thumbnail: _, media: _)):
                    return 0x10
                }
            }

            var info: Info {
                switch self {
                case .friends(let info):
                    return info
                case .zone(let info):
                    return info
                case .favorites(let info):
                    return info
                case .dataline(let info):
                    return info
                }
            }
        }
        case qq(QQSubtype)

        public enum WeiboSubtype {
            case `default`(info: Info, accessToken: String?)

            var info: Info {
                switch self {
                case .default(let info, _):
                    return info
                }
            }

            var accessToken: String? {
                switch self {
                case .default(_, let accessToken):
                    return accessToken
                }
            }
        }
        case weibo(WeiboSubtype)

        public enum AlipaySubtype {
            case friends(info: Info)
            case timeline(info: Info)

            var scene: NSNumber {
                switch self {
                case .friends:
                    return 0
                case .timeline:
                    return 1
                }
            }

            var info: Info {
                switch self {
                case .friends(let info):
                    return info
                case .timeline(let info):
                    return info
                }
            }
        }
        case alipay(AlipaySubtype)

        public enum TwitterSubtype {
            case `default`(info: Info, mediaIDs: [String]?, accessToken: String?, accessTokenSecret: String?)
//            case `photos`(info: Info, accessToken: String?, accessTokenSecret: String?)

            var info: Info {
                switch self {
                case .default(let info, _, _, _):
                    return info
//                case .photos(_, let info, _, _):
//                    return info
                }
            }

            var mediaIDs: [String]? {
                switch self {
                case .default(_, let mediaIDs, _, _):
                    return mediaIDs
//                case .photos(let mediaIDs, _, _, _):
//                    return mediaIDs
                }
            }

            var accessToken: String? {
                switch self {
                case .default(_, _,let accessToken, _):
                    return accessToken
//                case .photos(_, _, let accessToken, _):
//                    return accessToken
                }
            }

            var accessTokenSecret: String? {
                switch self {
                case .default(_, _, _,let accessTokenSecret):
                    return accessTokenSecret
//                case .photos(_, _, _, let accessTokenSecret):
//                    return accessTokenSecret
                }
            }

        }
        case twitter(TwitterSubtype)

        public var canBeDelivered: Bool {
            guard let account = sharedMonkeyKing.accountSet[self] else { return false }
            switch account {
            case .weibo, .twitter:
                return true
            default:
                break
            }
            return account.isAppInstalled
        }
    }

    public class func deliver(_ message: Message, completionHandler: @escaping DeliverCompletionHandler) {
        guard message.canBeDelivered else {
            completionHandler(.failure(.messageCanNotBeDelivered))
            return
        }
        sharedMonkeyKing.deliverCompletionHandler = completionHandler
        guard let account = sharedMonkeyKing.accountSet[message] else {
            completionHandler(.failure(.noAccount))
            return
        }
        let appID = account.appID
        switch message {
        case .weChat(let type):
            var weChatMessageInfo: [String: Any] = [
                "result": "1",
                "returnFromApp": "0",
                "scene": type.scene,
                "sdkver": "1.5",
                "command": "1010"
            ]
            let info = type.info
            if let title = info.title {
                weChatMessageInfo["title"] = title
            }
            if let description = info.description {
                weChatMessageInfo["description"] = description
            }
            if let thumbnailData = info.thumbnail?.monkeyking_compressedImageData {
                weChatMessageInfo["thumbData"] = thumbnailData
            }
            if let media = info.media {
                switch media {
                case .url(let url):
                    weChatMessageInfo["objectType"] = "5"
                    weChatMessageInfo["mediaUrl"] = url.absoluteString
                case .image(let image):
                    weChatMessageInfo["objectType"] = "2"
                    if let fileImageData = UIImageJPEGRepresentation(image, 1) {
                        weChatMessageInfo["fileData"] = fileImageData
                    }
                case .audio(let audioURL, let linkURL):
                    weChatMessageInfo["objectType"] = "3"
                    if let urlString = linkURL?.absoluteString {
                        weChatMessageInfo["mediaUrl"] = urlString
                    }
                    weChatMessageInfo["mediaDataUrl"] = audioURL.absoluteString
                case .video(let url):
                    weChatMessageInfo["objectType"] = "4"
                    weChatMessageInfo["mediaUrl"] = url.absoluteString
                case .file:
                    fatalError("WeChat not supports File type")
                }
            } else { // Text Share
                weChatMessageInfo["command"] = "1020"
            }
            let weChatMessage = [appID: weChatMessageInfo]
            guard let data = try? PropertyListSerialization.data(fromPropertyList: weChatMessage, format: .binary, options: 0) else { return }
            UIPasteboard.general.setData(data, forPasteboardType: "content")
            let weChatSchemeURLString = "weixin://app/\(appID)/sendreq/?"
            if !openURL(urlString: weChatSchemeURLString) {
                completionHandler(.failure(.sdk(reason: .invalidURLScheme)))
            }
        case .qq(let type):
            let callbackName = appID.monkeyking_qqCallbackName
            var qqSchemeURLString = "mqqapi://share/to_fri?"
            if let encodedAppDisplayName = Bundle.main.monkeyking_displayName?.monkeyking_base64EncodedString {
                qqSchemeURLString += "thirdAppDisplayName=" + encodedAppDisplayName
            } else {
                qqSchemeURLString += "thirdAppDisplayName=" + "nixApp" // Should not be there
            }
            qqSchemeURLString += "&version=1&cflag=\(type.scene)"
            qqSchemeURLString += "&callback_type=scheme&generalpastboard=1"
            qqSchemeURLString += "&callback_name=\(callbackName)"
            qqSchemeURLString += "&src_type=app&shareType=0&file_type="
            if let media = type.info.media {
                func handleNews(with url: URL, mediaType: String?) {
                    if let thumbnailData = type.info.thumbnail?.monkeyking_compressedImageData {
                        let dic = ["previewimagedata": thumbnailData]
                        let data = NSKeyedArchiver.archivedData(withRootObject: dic)
                        UIPasteboard.general.setData(data, forPasteboardType: "com.tencent.mqq.api.apiLargeData")
                    }
                    qqSchemeURLString += mediaType ?? "news"
                    guard let encodedURLString = url.absoluteString.monkeyking_base64AndURLEncodedString else {
                        completionHandler(.failure(.sdk(reason: .urlEncodeFailed)))
                        return
                    }
                    qqSchemeURLString += "&url=\(encodedURLString)"
                }
                switch media {
                case .url(let url):
                    handleNews(with: url, mediaType: "news")
                case .image(let image):
                    guard let imageData = UIImageJPEGRepresentation(image, 1) else {
                        completionHandler(.failure(.invalidImageData))
                        return
                    }
                    var dic = [
                        "file_data": imageData
                    ]
                    if let thumbnail = type.info.thumbnail, let thumbnailData = UIImageJPEGRepresentation(thumbnail, 1) {
                        dic["previewimagedata"] = thumbnailData
                    }
                    let data = NSKeyedArchiver.archivedData(withRootObject: dic)
                    UIPasteboard.general.setData(data, forPasteboardType: "com.tencent.mqq.api.apiLargeData")
                    qqSchemeURLString += "img"
                case .audio(let audioURL, _):
                    handleNews(with: audioURL, mediaType: "audio")
                case .video(let url):
                    handleNews(with: url, mediaType: nil) // No video type, default is news type.
                case .file(let fileData):
                    let data = NSKeyedArchiver.archivedData(withRootObject: ["file_data": fileData])
                    UIPasteboard.general.setData(data, forPasteboardType: "com.tencent.mqq.api.apiLargeData")
                    qqSchemeURLString += "localFile"
                    if let filename = type.info.description?.monkeyking_urlEncodedString {
                        qqSchemeURLString += "&fileName=\(filename)"
                    }
                }
                if let encodedTitle = type.info.title?.monkeyking_base64AndURLEncodedString {
                    qqSchemeURLString += "&title=\(encodedTitle)"
                }
                if let encodedDescription = type.info.description?.monkeyking_base64AndURLEncodedString {
                    qqSchemeURLString += "&objectlocation=pasteboard&description=\(encodedDescription)"
                }
                qqSchemeURLString += "&sdkv=2.9"

            } else { // Share Text
                // fix #75
                switch type {
                case .zone:
                    qqSchemeURLString += "qzone&title="
                default:
                    qqSchemeURLString += "text&file_data="
                }
                if let encodedDescription = type.info.description?.monkeyking_base64AndURLEncodedString {
                    qqSchemeURLString += "\(encodedDescription)"
                }
            }
            if !openURL(urlString: qqSchemeURLString) {
                completionHandler(.failure(.sdk(reason: .invalidURLScheme)))
            }
        case .weibo(let type):
            func errorReason(with reponseData: [String: Any]) -> Error.APIRequestReason {
                // ref: http://open.weibo.com/wiki/Error_code
                guard let errorCode = reponseData["error_code"] as? Int else {
                    return Error.APIRequestReason(type: .unrecognizedError, responseData: reponseData)
                }
                switch errorCode {
                case 21314, 21315, 21316, 21317, 21327, 21332:
                    return Error.APIRequestReason(type: .invalidToken, responseData: reponseData)
                default:
                    return Error.APIRequestReason(type: .unrecognizedError, responseData: reponseData)
                }
            }
            guard !sharedMonkeyKing.canOpenURL(urlString: "weibosdk://request") else {
                // App Share
                var messageInfo: [String: Any] = [
                    "__class": "WBMessageObject"
                ]
                let info = type.info
                if let description = info.description {
                    messageInfo["text"] = description
                }
                if let media = info.media {
                    switch media {
                    case .url(let url):
                        if let thumbnailData = info.thumbnail?.monkeyking_compressedImageData {
                            var mediaObject: [String: Any] = [
                                "__class": "WBWebpageObject",
                                "objectID": "identifier1"
                            ]
                            mediaObject["webpageUrl"] = url.absoluteString
                            mediaObject["title"] = info.title ?? ""
                            mediaObject["thumbnailData"] = thumbnailData
                            messageInfo["mediaObject"] = mediaObject
                        } else {
                            // Deliver text directly.
                            let text = info.description ?? ""
                            messageInfo["text"] = text.isEmpty ? url.absoluteString : text + " " + url.absoluteString
                        }
                    case .image(let image):
                        if let imageData = UIImageJPEGRepresentation(image, 1.0) {
                            messageInfo["imageObject"] = [
                                "imageData": imageData
                            ]
                        }
                    case .audio:
                        fatalError("Weibo not supports Audio type")
                    case .video:
                        fatalError("Weibo not supports Video type")
                    case .file:
                        fatalError("Weibo not supports File type")
                    }
                }
                let uuidString = UUID().uuidString
                let dict: [String: Any] = [
                    "__class": "WBSendMessageToWeiboRequest",
                    "message": messageInfo,
                    "requestID": uuidString
                ]
                let appData = NSKeyedArchiver.archivedData(withRootObject: [
                    "appKey": appID,
                    "bundleID": Bundle.main.monkeyking_bundleID ?? ""
                    ]
                )
                let messageData: [[String: Any]] = [
                    ["transferObject": NSKeyedArchiver.archivedData(withRootObject: dict)],
                    ["app": appData]
                ]
                UIPasteboard.general.items = messageData
                if !openURL(urlString: "weibosdk://request?id=\(uuidString)&sdkversion=003013000") {
                    completionHandler(.failure(.sdk(reason: .invalidURLScheme)))
                }
                return
            }
            // Weibo Web Share
            let info = type.info
            var parameters = [String: Any]()
            guard let accessToken = type.accessToken else {
                completionHandler(.failure(.noAccount))
                return
            }
            parameters["access_token"] = accessToken
            var status: [String?] = [info.title, info.description]
            var mediaType = Media.url(NSURL() as URL)
            if let media = info.media {
                switch media {
                case .url(let url):
                    status.append(url.absoluteString)
                    mediaType = Media.url(url)
                case .image(let image):
                    guard let imageData = UIImageJPEGRepresentation(image, 0.7) else {
                        completionHandler(.failure(.invalidImageData))
                        return
                    }
                    parameters["pic"] = imageData
                    mediaType = Media.image(image)
                case .audio:
                    fatalError("web Weibo not supports Audio type")
                case .video:
                    fatalError("web Weibo not supports Video type")
                case .file:
                    fatalError("web Weibo not supports File type")
                }
            }
            let statusText = status.flatMap({ $0 }).joined(separator: " ")
            parameters["status"] = statusText
            switch mediaType {
            case .url(_):
                let urlString = "https://api.weibo.com/2/statuses/update.json"
                sharedMonkeyKing.request(urlString, method: .post, parameters: parameters) { (responseData, HTTPResponse, error) in
                    var reason: Error.APIRequestReason
                    if error != nil {
                        reason = Error.APIRequestReason(type: .connectFailed, responseData: nil)
                        completionHandler(.failure(.apiRequest(reason: reason)))
                    } else if let responseData = responseData, (responseData["idstr"] as? String) == nil {
                        reason = errorReason(with: responseData)
                        completionHandler(.failure(.apiRequest(reason: reason)))
                    } else {
                        completionHandler(.success(nil))
                    }
                }
            case .image(_):
                let urlString = "https://upload.api.weibo.com/2/statuses/upload.json"
                sharedMonkeyKing.upload(urlString, parameters: parameters) { (responseData, HTTPResponse, error) in
                    var reason: Error.APIRequestReason
                    if error != nil {
                        reason = Error.APIRequestReason(type: .connectFailed, responseData: nil)
                        completionHandler(.failure(.apiRequest(reason: reason)))
                    } else if let responseData = responseData, (responseData["idstr"] as? String) == nil {
                        reason = errorReason(with: responseData)
                        completionHandler(.failure(.apiRequest(reason: reason)))
                    } else {
                        completionHandler(.success(nil))
                    }
                }
            case .audio:
                fatalError("web Weibo not supports Audio type")
            case .video:
                fatalError("web Weibo not supports Video type")
            case .file:
                fatalError("web Weibo not supports File type")
            }
        case .alipay(let type):
            let dictionary = createAlipayMessageDictionary(withScene: type.scene, info: type.info, appID: appID)
            guard let data = try? PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: 0) else {
                completionHandler(.failure(.sdk(reason: .serializeFailed)))
                return
            }
            UIPasteboard.general.setData(data, forPasteboardType: "com.alipay.openapi.pb.req.\(appID)")
            if !openURL(urlString: "alipayshare://platformapi/shareService?action=sendReq&shareId=\(appID)") {
                completionHandler(.failure(.sdk(reason: .invalidURLScheme)))
            }
        case .twitter(let type):
            // MARK: - Twitter Deliver
            guard let accessToken = type.accessToken,
                  let accessTokenSecret = type.accessTokenSecret,
                  let account = sharedMonkeyKing.accountSet[.twitter] else {
                completionHandler(.failure(.noAccount))
                return
            }

            let info = type.info
            var status = [info.title, info.description]
            var parameters = [String: Any]()
            var mediaType = Media.url(NSURL() as URL)
            if let media = info.media {
                switch media {
                case .url(let url):
                    status.append(url.absoluteString)
                    mediaType = Media.url(url)
                case .image(let image):
                    guard let imageData = UIImageJPEGRepresentation(image, 0.7) else {
                        completionHandler(.failure(.invalidImageData))
                        return
                    }
                    parameters["media"] = imageData
                    mediaType = Media.image(image)
                default:
                    fatalError("web Twitter not supports this type")
                }
            }

            switch mediaType {
            case .url(_):
                let statusText = status.flatMap({ $0 }).joined(separator: " ")
                let updateStatusAPI = "https://api.twitter.com/1.1/statuses/update.json"

                var parameters = ["status": statusText]
                if let mediaIDs = type.mediaIDs {
                    parameters["media_ids"] = mediaIDs.joined(separator: ",")
                }

                if case .twitter(let appID, let appKey, _) = account {
                    let oauthString = Networking.sharedInstance.authorizationHeader(for: .post, urlString: updateStatusAPI, appID: appID, appKey: appKey, accessToken: accessToken, accessTokenSecret: accessTokenSecret, parameters: parameters, isMediaUpload: true)
                    let headers = ["Authorization": oauthString]
                    // ref: https://dev.twitter.com/rest/reference/post/statuses/update
                    let urlString = "\(updateStatusAPI)?\(parameters.urlEncodedQueryString(using: .utf8))"
                    sharedMonkeyKing.request(urlString, method: .post, parameters: nil, headers: headers) { (responseData, URLResponse, error) in
                        var reason: Error.APIRequestReason
                        if error != nil {
                            reason = Error.APIRequestReason(type: .connectFailed, responseData: nil)
                            completionHandler(.failure(.apiRequest(reason: reason)))
                        } else {
                            if let HTTPResponse = URLResponse as? HTTPURLResponse,
                                HTTPResponse.statusCode == 200 {
                                completionHandler(.success(nil))
                                return
                            }
                            if let responseData = responseData,
                               let _ = responseData["errors"] {
                                reason = sharedMonkeyKing.errorReason(with: responseData, at: .twitter)
                                completionHandler(.failure(.apiRequest(reason: reason)))
                                return
                            }
                            let unrecognizedReason = Error.APIRequestReason(type: .unrecognizedError, responseData: responseData)
                            completionHandler(.failure(.apiRequest(reason: unrecognizedReason)))
                        }
                    }
                }
            case .image(_):
                let uploadMediaAPI = "https://upload.twitter.com/1.1/media/upload.json"
                if case .twitter(let appID, let appKey, _) = account {
                    // ref: https://dev.twitter.com/rest/media/uploading-media#keepinmind
                    let oauthString = Networking.sharedInstance.authorizationHeader(for: .post, urlString: uploadMediaAPI, appID: appID, appKey: appKey, accessToken: accessToken, accessTokenSecret: accessTokenSecret, parameters: nil, isMediaUpload: false)
                    let headers = ["Authorization": oauthString]

                    sharedMonkeyKing.upload(uploadMediaAPI, parameters: parameters, headers: headers) { (responseData, URLResponse, error) in
                        if let statusCode = (URLResponse as? HTTPURLResponse)?.statusCode,
                            statusCode == 200 {
                            completionHandler(.success(responseData))
                            return
                        }

                        var reason: Error.APIRequestReason
                        if let _ = error {
                            reason = Error.APIRequestReason(type: .connectFailed, responseData: nil)
                        } else {
                            reason = Error.APIRequestReason(type: .unrecognizedError, responseData: responseData)
                        }

                        completionHandler(.failure(.apiRequest(reason: reason)))
                    }

                }
            default:
                fatalError("web Twitter not supports this type")
            }

        }
    }
}

// MARK: Pay

extension MonkeyKing {

    public enum Order {
        /// You can custom URL scheme. Default "ap" + String(appID)
        /// ref: https://doc.open.alipay.com/docs/doc.htm?spm=a219a.7629140.0.0.piSRlm&treeId=204&articleId=105295&docType=1
        case alipay(urlString: String, scheme: String?)
        case weChat(urlString: String)

        public var canBeDelivered: Bool {
            var scheme = ""
            switch self {
            case .alipay:
                scheme = "alipay://"
            case .weChat:
                scheme = "weixin://"
            }
            guard !scheme.isEmpty else { return false }
            return sharedMonkeyKing.canOpenURL(urlString: scheme)
        }
    }

    public class func deliver(_ order: Order, completionHandler: @escaping PayCompletionHandler) {
        if !order.canBeDelivered {
            completionHandler(false)
            return
        }
        sharedMonkeyKing.payCompletionHandler = completionHandler
        switch order {
        case .weChat(let urlString):
            if !openURL(urlString: urlString) {
                completionHandler(false)
            }
        case let .alipay(urlString, scheme):
            sharedMonkeyKing.customAlipayOrderScheme = scheme
            if !openURL(urlString: urlString) {
                completionHandler(false)
            }
        }
    }
}

// MARK: OAuth

extension MonkeyKing {

    public class func oauth(for platform: SupportedPlatform, scope: String? = nil, completionHandler: @escaping OAuthCompletionHandler) {
        guard let account = sharedMonkeyKing.accountSet[platform] else { return }
        guard account.isAppInstalled || account.canWebOAuth else {
            let error = NSError(domain: "App is not installed", code: -2, userInfo: nil)
            completionHandler(nil, nil, error)
            return
        }
        sharedMonkeyKing.oauthCompletionHandler = completionHandler
        switch account {
        case .weChat(let appID, _):
            let scope = scope ?? "snsapi_userinfo"
            if !account.isAppInstalled {
                // SMS OAuth
                // uid??
                let accessTokenAPI = "https://open.weixin.qq.com/connect/mobilecheck?appid=\(appID)&uid=1926559385"
                addWebView(withURLString: accessTokenAPI)
            } else {
                if !openURL(urlString: "weixin://app/\(appID)/auth/?scope=\(scope)&state=Weixinauth") {
                    completionHandler(nil, nil, NSError(domain: "OAuth Error, cannot open url weixin://", code: -1, userInfo: nil))
                }
            }
        case .qq(let appID):
            let scope = scope ?? ""
            guard !account.isAppInstalled else {
                let appName = Bundle.main.monkeyking_displayName ?? "nixApp"
                let dic = [
                    "app_id": appID,
                    "app_name": appName,
                    "client_id": appID,
                    "response_type": "token",
                    "scope": scope,
                    "sdkp": "i",
                    "sdkv": "2.9",
                    "status_machine": UIDevice.current.model,
                    "status_os": UIDevice.current.systemVersion,
                    "status_version": UIDevice.current.systemVersion
                ]
                let data = NSKeyedArchiver.archivedData(withRootObject: dic)
                UIPasteboard.general.setData(data, forPasteboardType: "com.tencent.tencent\(appID)")
                if !openURL(urlString: "mqqOpensdkSSoLogin://SSoLogin/tencent\(appID)/com.tencent.tencent\(appID)?generalpastboard=1") {
                    completionHandler(nil, nil, NSError(domain: "OAuth Error, cannot open url mqqOpensdkSSoLogin://", code: -1, userInfo: nil))
                }
                return
            }
            // Web OAuth
            let accessTokenAPI = "https://xui.ptlogin2.qq.com/cgi-bin/xlogin?appid=716027609&pt_3rd_aid=209656&style=35&s_url=http%3A%2F%2Fconnect.qq.com&refer_cgi=m_authorize&client_id=\(appID)&redirect_uri=auth%3A%2F%2Fwww.qq.com&response_type=token&scope=\(scope)"
            addWebView(withURLString: accessTokenAPI)
        case .weibo(let appID, _, let redirectURL):
            let scope = scope ?? "all"
            guard !account.isAppInstalled else {
                let uuidString = UUID().uuidString
                let transferObjectData = NSKeyedArchiver.archivedData(withRootObject: [
                    "__class": "WBAuthorizeRequest",
                    "redirectURI": redirectURL,
                    "requestID": uuidString,
                    "scope": scope
                    ]
                )
                let userInfoData = NSKeyedArchiver.archivedData(withRootObject: [
                    "mykey": "as you like",
                    "SSO_From": "SendMessageToWeiboViewController"
                    ]
                )
                let appData = NSKeyedArchiver.archivedData(withRootObject: [
                    "appKey": appID,
                    "bundleID": Bundle.main.monkeyking_bundleID ?? "",
                    "name": Bundle.main.monkeyking_displayName ?? ""
                    ]
                )
                let authItems: [[String: Any]] = [
                    ["transferObject": transferObjectData],
                    ["userInfo": userInfoData],
                    ["app": appData]
                ]
                UIPasteboard.general.items = authItems
                if !openURL(urlString: "weibosdk://request?id=\(uuidString)&sdkversion=003013000") {
                    completionHandler(nil, nil, NSError(domain: "OAuth Error, cannot open url weibosdk://", code: -1, userInfo: nil))
                }
                return
            }
            // Web OAuth
            let accessTokenAPI = "https://open.weibo.cn/oauth2/authorize?client_id=\(appID)&response_type=code&redirect_uri=\(redirectURL)&scope=\(scope)"
            addWebView(withURLString: accessTokenAPI)
        case .pocket(let appID):
            guard let startIndex = appID.range(of: "-")?.lowerBound else {
                return
            }
            let prefix = appID.substring(to: startIndex)
            let redirectURLString = "pocketapp\(prefix):authorizationFinished"
            var _requestToken: String?
            if case .pocket(let token) = platform {
                _requestToken = token
            }
            guard let requestToken = _requestToken else { return }
            guard !account.isAppInstalled else {
                let requestTokenAPI = "pocket-oauth-v1:///authorize?request_token=\(requestToken)&redirect_uri=\(redirectURLString)"
                if !openURL(urlString: requestTokenAPI) {
                    completionHandler(nil, nil, NSError(domain: "OAuth Error, cannot open url pocket-oauth-v1://", code: -1, userInfo: nil))
                }
                return
            }
            let requestTokenAPI = "https://getpocket.com/auth/authorize?request_token=\(requestToken)&redirect_uri=\(redirectURLString)"
            DispatchQueue.main.async {
                addWebView(withURLString: requestTokenAPI)
            }
        case .twitter(let appID, let appKey, let redirectURL):
            sharedMonkeyKing.twitterAuthenticate(appID: appID, appKey: appKey, redirectURL: redirectURL)
        case .alipay:
            break
        }
    }

    // Twitter Authenticate
    // https://dev.twitter.com/web/sign-in/implementing

    fileprivate func twitterAuthenticate(appID: String, appKey: String, redirectURL: String) {

        let requestTokenAPI = "https://api.twitter.com/oauth/request_token"
        let oauthString = Networking.sharedInstance.authorizationHeader(for: .post, urlString: requestTokenAPI, appID: appID, appKey: appKey, accessToken: nil, accessTokenSecret: nil, parameters: ["oauth_callback": redirectURL], isMediaUpload: false)
        let oauthHeader = ["Authorization": oauthString]
        Networking.sharedInstance.request(requestTokenAPI, method: .post, parameters: nil, encoding: .url, headers: oauthHeader) { (responseData, httpResponse, error) in
            if let responseData = responseData,
                let requestToken = (responseData["oauth_token"] as? String) {
                let loginURL = "https://api.twitter.com/oauth/authenticate?oauth_token=\(requestToken)"
                MonkeyKing.addWebView(withURLString: loginURL)
            }
        }
    }

    fileprivate func twitterAccessToken(requestToken: String, verifer: String) {
        for case let .twitter(appID, appKey, _) in accountSet {
            let accessTokenAPI = "https://api.twitter.com/oauth/access_token"
            let parameters = ["oauth_token": requestToken, "oauth_verifier": verifer]
            let headerString = Networking.sharedInstance.authorizationHeader(for: .post, urlString: accessTokenAPI, appID: appID, appKey: appKey, accessToken: nil, accessTokenSecret: nil, parameters: parameters, isMediaUpload: false)
            let oauthHeader = ["Authorization": headerString]

            Networking.sharedInstance.request(accessTokenAPI, method: .post, parameters: nil, encoding: .url, headers: oauthHeader) { (responseData, httpResponse, error) in
//                MonkeyKing.sharedMonkeyKing.oauthCompletionHandler?(responseData, httpResponse, error)

            }
        }
    }

}

// MARK: WKNavigationDelegate

extension MonkeyKing: WKNavigationDelegate {

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        // Pocket OAuth
        if let errorString = (error as NSError).userInfo["ErrorFailingURLStringKey"] as? String, errorString.hasSuffix(":authorizationFinished") {
            removeWebView(webView, tuples: (nil, nil, nil))
            return
        }
        // Failed to connect network
        activityIndicatorViewAction(webView, stop: true)
        addCloseButton()
        let detailLabel = UILabel()
        detailLabel.text = "无法连接，请检查网络后重试"
        detailLabel.textColor = UIColor.gray
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        let centerX = NSLayoutConstraint(item: detailLabel, attribute: .centerX, relatedBy: .equal, toItem: webView, attribute: .centerX, multiplier: 1.0, constant: 0.0)
        let centerY = NSLayoutConstraint(item: detailLabel, attribute: .centerY, relatedBy: .equal, toItem: webView, attribute: .centerY, multiplier: 1.0, constant: -50.0)
        webView.addSubview(detailLabel)
        webView.addConstraints([centerX,centerY])
        webView.scrollView.alwaysBounceVertical = false
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        activityIndicatorViewAction(webView, stop: true)
        addCloseButton()
        guard let urlString = webView.url?.absoluteString else { return }
        var scriptString = ""
        if urlString.contains("getpocket.com") {
            scriptString += "document.querySelector('div.toolbar').style.display = 'none';"
            scriptString += "document.querySelector('a.extra_action').style.display = 'none';"
            scriptString += "var rightButton = $('.toolbarContents div:last-child');"
            scriptString += "if (rightButton.html() == 'Log In') {rightButton.click()}"
        } else if urlString.contains("open.weibo.cn") {
            scriptString += "document.querySelector('aside.logins').style.display = 'none';"
        }
        webView.evaluateJavaScript(scriptString, completionHandler: nil)
    }

    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        guard let url = webView.url else {
            webView.stopLoading()
            return
        }

        // twitter access token
        for case let .twitter(appID, appKey, redirectURL) in accountSet {
            if url.absoluteString.hasPrefix(redirectURL) {

                var parametersString = url.absoluteString
                for _ in (0...redirectURL.characters.count) {
                    parametersString.remove(at: parametersString.startIndex)
                }
                let params = parametersString.queryStringParameters

                if let token = params["oauth_token"],
                   let verifer = params["oauth_verifier"] {

                    let accessTokenAPI = "https://api.twitter.com/oauth/access_token"
                    let parameters = ["oauth_token": token, "oauth_verifier": verifer]
                    let headerString = Networking.sharedInstance.authorizationHeader(for: .post, urlString: accessTokenAPI, appID: appID, appKey: appKey, accessToken: nil, accessTokenSecret: nil, parameters: parameters, isMediaUpload: false)
                    let oauthHeader = ["Authorization": headerString]

                    request(accessTokenAPI, method: .post, parameters: nil, encoding: .url, headers: oauthHeader) { [weak self] (responseData, httpResponse, error) in
                        DispatchQueue.main.async { [weak self] in
                            self?.removeWebView(webView, tuples: (responseData, httpResponse, error))
                        }
                    }

                }

                return
            }
        }

        // QQ Web OAuth
        guard url.absoluteString.contains("&access_token=") && url.absoluteString.contains("qq.com") else {
            return
        }
        guard let fragment = url.fragment?.characters.dropFirst(), let newURL = URL(string: "https://qzs.qq.com/?\(String(fragment))") else {
            return
        }
        let queryDictionary = newURL.monkeyking_queryDictionary as [String: Any]
        removeWebView(webView, tuples: (queryDictionary, nil, nil))
    }

    public func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        guard let url = webView.url else { return }
        // WeChat OAuth
        if url.absoluteString.hasPrefix("wx") {
            let queryDictionary = url.monkeyking_queryDictionary
            guard let code = queryDictionary["code"] as? String else {
                return
            }
            MonkeyKing.fetchWeChatOAuthInfoByCode(code: code) { [weak self] (info, response, error) in
                self?.removeWebView(webView, tuples: (info, response, error))
            }
        } else {
            // Weibo OAuth
            for case let .weibo(appID, appKey, redirectURL) in accountSet {
                if url.absoluteString.lowercased().hasPrefix(redirectURL) {
                    webView.stopLoading()
                    guard let code = url.monkeyking_queryDictionary["code"] as? String else { return }
                    var accessTokenAPI = "https://api.weibo.com/oauth2/access_token?"
                    accessTokenAPI += "client_id=" + appID
                    accessTokenAPI += "&client_secret=" + appKey
                    accessTokenAPI += "&grant_type=authorization_code"
                    accessTokenAPI += "&redirect_uri=" + redirectURL
                    accessTokenAPI += "&code=" + code
                    activityIndicatorViewAction(webView, stop: false)
                    request(accessTokenAPI, method: .post) { [weak self] (json, response, error) in
                        DispatchQueue.main.async { [weak self] in
                            self?.removeWebView(webView, tuples: (json, response, error))
                        }
                    }
                }
            }
        }
    }
}

// MARK: Error

extension MonkeyKing {

    public enum Error: Swift.Error {
        case noAccount
        case messageCanNotBeDelivered
        case invalidImageData

        public enum SDKReason {
            case unknown
            case invalidURLScheme
            case urlEncodeFailed
            case serializeFailed
        }
        case sdk(reason: SDKReason)

        public struct APIRequestReason {
            public enum `Type` {
                case unrecognizedError
                case connectFailed
                case invalidToken
            }
            public var type: Type
            public var responseData: [String: Any]?
        }
        case apiRequest(reason: APIRequestReason)
    }

    func errorReason(with responseData: [String: Any], at platform: SupportedPlatform) -> Error.APIRequestReason {

        let unrecognizedReason = Error.APIRequestReason(type: .unrecognizedError, responseData: responseData)
        switch platform {
        case .twitter:

            //ref: https://dev.twitter.com/overview/api/response-codes
            guard let errorCode = responseData["code"] as? Int else {
                return unrecognizedReason
            }
            switch errorCode {
            case 89, 99:
                return Error.APIRequestReason(type: .invalidToken, responseData: responseData)
            default:
                return unrecognizedReason
            }

        case .weibo:

            // ref: http://open.weibo.com/wiki/Error_code
            guard let errorCode = responseData["error_code"] as? Int else {
                return unrecognizedReason
            }
            switch errorCode {
            case 21314, 21315, 21316, 21317, 21327, 21332:
                return Error.APIRequestReason(type: .invalidToken, responseData: responseData)
            default:
                return unrecognizedReason
            }

        default:
            return unrecognizedReason
        }
    }

}


extension MonkeyKing.Error: LocalizedError {

    public var errorDescription: String {

        switch self {
        case .invalidImageData:
            return "Convert image to data failed."
        case .noAccount:
            return "There no invalid developer account."
        case .messageCanNotBeDelivered:
            return "Message can't be delivered."
        case .apiRequest(reason: let reason):

            switch reason.type {
            case .invalidToken:
                return "The token is invalid or expired."
            case .connectFailed:
                return "Can't open the API link."
            default:
                return "API invoke failed."
            }

        default:
            return "Some problems happenned in MonkeyKing."
        }
        
    }
    
}

// MARK: Private Methods

extension MonkeyKing {

    fileprivate class func generateWebView() -> WKWebView {
        let webView = WKWebView()
        let screenBounds = UIScreen.main.bounds
        webView.frame = CGRect(origin: CGPoint(x: 0, y: screenBounds.height),
                               size: CGSize(width: screenBounds.width, height: screenBounds.height - 20))
        webView.navigationDelegate = sharedMonkeyKing
        webView.backgroundColor = UIColor(red: 247/255, green: 247/255, blue: 247/255, alpha: 1.0)
        webView.scrollView.backgroundColor = webView.backgroundColor
        UIApplication.shared.keyWindow?.addSubview(webView)
        return webView
    }

    fileprivate class func fetchWeChatOAuthInfoByCode(code: String, completionHandler: @escaping OAuthCompletionHandler) {
        var appID = ""
        var appKey = ""
        for case let .weChat(id, key) in sharedMonkeyKing.accountSet {
            guard let key = key else {
                completionHandler(["code": code], nil, nil)
                return
            }
            appID = id
            appKey = key
        }
        var accessTokenAPI = "https://api.weixin.qq.com/sns/oauth2/access_token"
        accessTokenAPI += "?grant_type=authorization_code"
        accessTokenAPI += "&appid=\(appID)"
        accessTokenAPI += "&secret=\(appKey)"
        accessTokenAPI += "&code=\(code)"
        // OAuth
        sharedMonkeyKing.request(accessTokenAPI, method: .get) { (json, response, error) in
            completionHandler(json, response, error)
        }
    }

    fileprivate class func createAlipayMessageDictionary(withScene scene: NSNumber, info: Info, appID: String) -> [String: Any] {
        enum AlipayMessageType {
            case text
            case image(UIImage)
            case url(URL)
        }
        let keyUID = "CF$UID"
        let keyClass = "$class"
        let keyClasses = "$classes"
        let keyClassname = "$classname"
        var messageType: AlipayMessageType = .text
        if let media = info.media {
            switch media {
            case .url(let url):
                messageType = .url(url)
            case .image(let image):
                messageType = .image(image)
            case .audio:
                fatalError("Alipay not supports Audio type")
            case .video:
                fatalError("Alipay not supports Video type")
            case .file:
                fatalError("Alipay not supports File type")
            }
        } else { // Text
            messageType = .text
        }
        // Public Items
        let UIDValue: Int
        let APMediaType: String
        switch messageType {
        case .text:
            UIDValue = 20
            APMediaType = "APShareTextObject"
        case .image:
            UIDValue = 21
            APMediaType = "APShareImageObject"
        case .url:
            UIDValue = 24
            APMediaType = "APShareWebObject"
        }
        let publicObjectsItem0 = "$null"
        let publicObjectsItem1: [String: Any] = [
            keyClass: [keyUID: UIDValue],
            "NS.keys": [
                [keyUID: 2],
                [keyUID: 3]
            ],
            "NS.objects": [
                [keyUID: 4],
                [keyUID: 11]
            ]
        ]
        let publicObjectsItem2 = "app"
        let publicObjectsItem3 = "req"
        let publicObjectsItem4: [String: Any] = [
            keyClass: [keyUID: 10],
            "appKey": [keyUID: 6],
            "bundleId": [keyUID: 7],
            "name": [keyUID: 5],
            "scheme": [keyUID: 8],
            "sdkVersion": [keyUID: 9]
        ]
        let publicObjectsItem5 = Bundle.main.monkeyking_displayName ?? "China"
        let publicObjectsItem6 = appID
        let publicObjectsItem7 = Bundle.main.monkeyking_bundleID ?? "com.nixWork.China"
        let publicObjectsItem8 = "ap\(appID)"
        let publicObjectsItem9 = "1.1.0.151016" // SDK Version
        let publicObjectsItem10: [String: Any] = [
            keyClasses: ["APSdkApp", "NSObject"],
            keyClassname: "APSdkApp"
        ]
        let publicObjectsItem11: [String: Any] = [
            keyClass: [keyUID: UIDValue - 1],
            "message": [keyUID: 13],
            "scene": [keyUID: UIDValue - 2],
            "type": [keyUID: 12]
        ]
        let publicObjectsItem12: NSNumber = 0
        let publicObjectsItem13: [String: Any] = [      // For Text(13) && Image(13)
            keyClass: [keyUID: UIDValue - 3],
            "mediaObject": [keyUID: 14]
        ]
        let publicObjectsItem14: [String: Any] = [      // For Image(16) && URL(17)
            keyClasses: ["NSMutableData", "NSData", "NSObject"],
            keyClassname: "NSMutableData"
        ]
        let publicObjectsItem16: [String: Any] = [
            keyClasses: [APMediaType, "NSObject"],
            keyClassname: APMediaType
        ]
        let publicObjectsItem17: [String: Any] = [
            keyClasses: ["APMediaMessage", "NSObject"],
            keyClassname: "APMediaMessage"
        ]
        let publicObjectsItem18: NSNumber = scene
        let publicObjectsItem19: [String: Any] = [
            keyClasses: ["APSendMessageToAPReq", "APBaseReq", "NSObject"],
            keyClassname: "APSendMessageToAPReq"
        ]
        let publicObjectsItem20: [String: Any] = [
            keyClasses: ["NSMutableDictionary", "NSDictionary", "NSObject"],
            keyClassname: "NSMutableDictionary"
        ]
        var objectsValue: [Any] = [
            publicObjectsItem0, publicObjectsItem1, publicObjectsItem2, publicObjectsItem3,
            publicObjectsItem4, publicObjectsItem5, publicObjectsItem6, publicObjectsItem7,
            publicObjectsItem8, publicObjectsItem9, publicObjectsItem10, publicObjectsItem11,
            publicObjectsItem12
        ]
        switch messageType {
        case .text:
            let textObjectsItem14: [String: Any] = [
                keyClass: [keyUID: 16],
                "text": [keyUID: 15]
            ]
            let textObjectsItem15 = info.title ?? "Input Text"
            objectsValue = objectsValue + [publicObjectsItem13, textObjectsItem14, textObjectsItem15]
        case .image(let image):
            let imageObjectsItem14: [String: Any] = [
                keyClass: [keyUID: 17],
                "imageData": [keyUID: 15]
            ]
            let imageData = UIImageJPEGRepresentation(image, 0.7) ?? Data()
            let imageObjectsItem15: [String: Any] = [
                keyClass: [keyUID: 16],
                "NS.data": imageData
            ]
            objectsValue = objectsValue + [publicObjectsItem13, imageObjectsItem14, imageObjectsItem15, publicObjectsItem14]
        case .url(let url):
            let urlObjectsItem13: [String: Any] = [
                keyClass: [keyUID: 21],
                "desc": [keyUID: 15],
                "mediaObject": [keyUID: 18],
                "thumbData": [keyUID: 16],
                "title": [keyUID: 14]
            ]
            let thumbnailData = info.thumbnail?.monkeyking_compressedImageData ?? Data()
            let urlObjectsItem14 = info.title ?? "Input Title"
            let urlObjectsItem15 = info.description ?? "Input Description"
            let urlObjectsItem16: [String: Any] = [
                keyClass: [keyUID: 17],
                "NS.data": thumbnailData
            ]
            let urlObjectsItem18: [String: Any] = [
                keyClass: [keyUID: 20],
                "webpageUrl": [keyUID: 19]
            ]
            let urlObjectsItem19 = url.absoluteString
            objectsValue = objectsValue + [
                urlObjectsItem13,
                urlObjectsItem14,
                urlObjectsItem15,
                urlObjectsItem16,
                publicObjectsItem14,
                urlObjectsItem18,
                urlObjectsItem19
            ]
        }
        objectsValue += [publicObjectsItem16, publicObjectsItem17, publicObjectsItem18, publicObjectsItem19, publicObjectsItem20]
        let dictionary: [String: Any] = [
            "$archiver": "NSKeyedArchiver",
            "$objects": objectsValue,
            "$top": ["root" : [keyUID: 1]],
            "$version": 100000
        ]
        return dictionary
    }

    fileprivate func request(_ urlString: String, method: Networking.Method, parameters: [String: Any]? = nil, encoding: Networking.ParameterEncoding = .url, headers: [String: String]? = nil, completionHandler: @escaping Networking.NetworkingResponseHandler) {
        Networking.sharedInstance.request(urlString, method: method, parameters: parameters, encoding: encoding, headers: headers, completionHandler: completionHandler)
    }

    fileprivate func upload(_ urlString: String, parameters: [String: Any], headers: [String: String]? = nil,completionHandler: @escaping Networking.NetworkingResponseHandler) {
        Networking.sharedInstance.upload(urlString, parameters: parameters, headers: headers, completionHandler: completionHandler)
    }

    fileprivate class func addWebView(withURLString urlString: String) {
        if nil == MonkeyKing.sharedMonkeyKing.webView {
            MonkeyKing.sharedMonkeyKing.webView = generateWebView()
        }
        guard let url = URL(string: urlString), let webView = MonkeyKing.sharedMonkeyKing.webView else { return }
        webView.load(URLRequest(url: url))
        let activityIndicatorView = UIActivityIndicatorView(frame: CGRect(x: 0.0, y: 0.0, width: 20.0, height: 20.0))
        activityIndicatorView.center = CGPoint(x: webView.bounds.midX, y: webView.bounds.midY + 30.0)
        activityIndicatorView.activityIndicatorViewStyle = .gray
        webView.scrollView.addSubview(activityIndicatorView)
        activityIndicatorView.startAnimating()
        UIView.animate(withDuration: 0.32, delay: 0.0, options: .curveEaseOut, animations: {
            webView.frame.origin.y = 20.0
        }, completion: nil)
    }

    fileprivate func addCloseButton() {
        guard webView != nil else {
            return
        }
        let closeButton = CloseButton(type: .custom)
        closeButton.frame = CGRect(origin: CGPoint(x: UIScreen.main.bounds.width - 50.0, y: 4.0),
                                   size: CGSize(width: 44.0, height: 44.0))
        closeButton.addTarget(self, action: #selector(closeOuathView), for: .touchUpInside)
        webView!.addSubview(closeButton)
    }

    @objc fileprivate func closeOuathView() {
        guard webView != nil else { return }
        let error = NSError(domain: "User Cancelled", code: -1, userInfo: nil)
        removeWebView(webView!, tuples: (nil, nil, error))
    }

    fileprivate func removeWebView(_ webView: WKWebView, tuples: ([String: Any]?, URLResponse?, Swift.Error?)?) {
        activityIndicatorViewAction(webView, stop: true)
        webView.stopLoading()
        UIView.animate(withDuration: 0.3, delay: 0.0, options: .curveEaseOut, animations: {
            webView.frame.origin.y = UIScreen.main.bounds.height
        }, completion: { [weak self] _ in
            webView.removeFromSuperview()
            MonkeyKing.sharedMonkeyKing.webView = nil
            self?.oauthCompletionHandler?(tuples?.0, tuples?.1, tuples?.2)
        })
    }

    fileprivate func activityIndicatorViewAction(_ webView: WKWebView, stop: Bool) {
        for subview in webView.scrollView.subviews {
            if let activityIndicatorView = subview as? UIActivityIndicatorView {
                guard stop else {
                    activityIndicatorView.startAnimating()
                    return
                }
                activityIndicatorView.stopAnimating()
            }
        }
    }

    fileprivate class func openURL(urlString: String) -> Bool {
        guard let url = URL(string: urlString) else { return false }
        return UIApplication.shared.openURL(url)
    }

    fileprivate func canOpenURL(urlString: String) -> Bool {
        guard let url = URL(string: urlString) else { return false }
        return UIApplication.shared.canOpenURL(url)
    }
}

// MARK: Private Extensions

private extension Set {

    subscript(platform: MonkeyKing.SupportedPlatform) -> MonkeyKing.Account? {
        let accountSet = MonkeyKing.sharedMonkeyKing.accountSet
        switch platform {
        case .weChat:
            for account in accountSet {
                if case .weChat = account {
                    return account
                }
            }
        case .qq:
            for account in accountSet {
                if case .qq = account {
                    return account
                }
            }
        case .weibo:
            for account in accountSet {
                if case .weibo = account {
                    return account
                }
            }
        case .pocket:
            for account in accountSet {
                if case .pocket = account {
                    return account
                }
            }
        case .alipay:
            for account in accountSet {
                if case .alipay = account {
                    return account
                }
            }
        case .twitter:
            for account in accountSet {
                if case .twitter = account {
                    return account
                }
            }
        }
        return nil
    }

    subscript(platform: MonkeyKing.Message) -> MonkeyKing.Account? {
        let accountSet = MonkeyKing.sharedMonkeyKing.accountSet
        switch platform {
        case .weChat(_):
            for account in accountSet {
                if case .weChat = account {
                    return account
                }
            }
        case .qq(_):
            for account in accountSet {
                if case .qq = account {
                    return account
                }
            }
        case .weibo(_):
            for account in accountSet {
                if case .weibo = account {
                    return account
                }
            }
        case .alipay(_):
            for account in accountSet {
                if case .alipay = account {
                    return account
                }
            }
        case .twitter(_):
            for account in accountSet {
                if case .twitter = account {
                    return account
                }
            }
        }
        return nil
    }
}

private extension Bundle {

    var monkeyking_displayName: String? {
        func getNameByInfo(_ info: [String : Any]) -> String? {
            guard let displayName = info["CFBundleDisplayName"] as? String else {
                return info["CFBundleName"] as? String
            }
            return displayName
        }
        var info = infoDictionary
        if let localizedInfo = localizedInfoDictionary, !localizedInfo.isEmpty {
            for (key, value) in localizedInfo {
                info?[key] = value
            }
        }
        guard let unwrappedInfo = info else {
            return nil
        }
        return getNameByInfo(unwrappedInfo)
    }

    var monkeyking_bundleID: String? {
        return object(forInfoDictionaryKey: "CFBundleIdentifier") as? String
    }
}

private extension String {

    var monkeyking_base64EncodedString: String? {
        return data(using: .utf8)?.base64EncodedString(options: NSData.Base64EncodingOptions(rawValue: 0))
    }

    var monkeyking_urlEncodedString: String? {
        return addingPercentEncoding(withAllowedCharacters: CharacterSet.urlHostAllowed)
    }

    var monkeyking_base64AndURLEncodedString: String? {
        return monkeyking_base64EncodedString?.monkeyking_urlEncodedString
    }

    var monkeyking_urlDecodedString: String? {
        return replacingOccurrences(of: "+", with: " ").removingPercentEncoding
    }

    var monkeyking_qqCallbackName: String {
        var hexString = String(format: "%02llx", (self as NSString).longLongValue)
        while hexString.characters.count < 8 {
            hexString = "0" + hexString
        }
        return "QQ" + hexString
    }
}

private extension Data {

    var monkeyking_json: [String: Any]? {
        do {
            return try JSONSerialization.jsonObject(with: self, options: .allowFragments) as? [String: Any]
        } catch {
            return nil
        }
    }
}

private extension URL {

    var monkeyking_queryDictionary: [String: Any] {
        let components = URLComponents(url: self, resolvingAgainstBaseURL: false)
        guard let items = components?.queryItems else {
            return [:]
        }
        var infos = [String: Any]()
        items.forEach {
            if let value = $0.value {
                infos[$0.name] = value
            }
        }
        return infos
    }
}

private extension UIImage {

    var monkeyking_compressedImageData: Data? {
        var compressionQuality: CGFloat = 0.7
        func compressedDataOfImage(_ image: UIImage) -> Data? {
            let maxHeight: CGFloat = 240.0
            let maxWidth: CGFloat = 240.0
            var actualHeight: CGFloat = image.size.height
            var actualWidth: CGFloat = image.size.width
            var imgRatio: CGFloat = actualWidth/actualHeight
            let maxRatio: CGFloat = maxWidth/maxHeight
            if actualHeight > maxHeight || actualWidth > maxWidth {
                if imgRatio < maxRatio { // adjust width according to maxHeight
                    imgRatio = maxHeight / actualHeight
                    actualWidth = imgRatio * actualWidth
                    actualHeight = maxHeight
                } else if imgRatio > maxRatio { // adjust height according to maxWidth
                    imgRatio = maxWidth / actualWidth
                    actualHeight = imgRatio * actualHeight
                    actualWidth = maxWidth
                } else {
                    actualHeight = maxHeight
                    actualWidth = maxWidth
                }
            }
            let rect = CGRect(x: 0.0, y: 0.0, width: actualWidth, height: actualHeight)
            UIGraphicsBeginImageContext(rect.size)
            defer {
                UIGraphicsEndImageContext()
            }
            image.draw(in: rect)
            let imageData = UIGraphicsGetImageFromCurrentImageContext().flatMap({
                UIImageJPEGRepresentation($0, compressionQuality)
            })
            return imageData
        }
        let fullImageData = UIImageJPEGRepresentation(self, compressionQuality)
        guard var imageData = fullImageData else { return nil }
        let minCompressionQuality: CGFloat = 0.01
        let dataLengthCeiling: Int = 31500
        while imageData.count > dataLengthCeiling && compressionQuality > minCompressionQuality {
            compressionQuality -= 0.1
            guard let image = UIImage(data: imageData) else { break }
            if let compressedImageData = compressedDataOfImage(image) {
                imageData = compressedImageData
            } else {
                break
            }
        }
        return imageData
    }
}

class CloseButton: UIButton {

    override func draw(_ rect: CGRect) {
        let circleWidth: CGFloat = 28.0
        let circlePathX = (rect.width - circleWidth) / 2.0
        let circlePathY = (rect.height - circleWidth) / 2.0
        let circlePathRect = CGRect(x: circlePathX, y: circlePathY, width: circleWidth, height: circleWidth)
        let circlePath = UIBezierPath(ovalIn: circlePathRect)
        UIColor(white: 0.8, alpha: 1.0).setFill()
        circlePath.fill()
        let xPath = UIBezierPath()
        xPath.lineCapStyle = .round
        xPath.lineWidth = 3.0
        let offset: CGFloat = (bounds.width - circleWidth) / 2.0
        xPath.move(to: CGPoint(x: offset + circleWidth / 3.0, y: offset + circleWidth / 3.0))
        xPath.addLine(to: CGPoint(x: offset + 2.0 * circleWidth / 3.0, y: offset + 2.0 * circleWidth / 3.0))
        xPath.move(to: CGPoint(x: offset + circleWidth / 3.0, y: offset + 2.0 * circleWidth / 3.0))
        xPath.addLine(to: CGPoint(x: offset + 2.0 * circleWidth / 3.0, y: offset + circleWidth / 3.0))
        UIColor.white.setStroke()
        xPath.stroke()
    }
}
