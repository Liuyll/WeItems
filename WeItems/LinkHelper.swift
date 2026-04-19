import UIKit

/// 购买链接识别 & 跳转工具
enum LinkHelper {
    
    enum AppTarget {
        case taobao
        case jd
        case none
        
        var appName: String {
            switch self {
            case .taobao: return "淘宝"
            case .jd: return "京东"
            case .none: return ""
            }
        }
        
        var scheme: String {
            switch self {
            case .taobao: return "taobao://"
            case .jd: return "openapp.jdmobile://virtual?params=%7B%22category%22%3A%22jump%22%2C%22des%22%3A%22getCoupon%22%7D"
            case .none: return ""
            }
        }
    }
    
    /// 识别链接中包含的电商平台
    static func detectApp(in link: String) -> AppTarget {
        let lower = link.lowercased()
        let taobaoKeywords = ["taobao.com", "tb.cn", "tmall.com", "m.tb.cn", "taobao", "淘宝", "天猫"]
        for keyword in taobaoKeywords {
            if lower.contains(keyword) { return .taobao }
        }
        let jdKeywords = ["jd.com", "jd.cn", "3.cn", "jingdong", "京东"]
        for keyword in jdKeywords {
            if lower.contains(keyword) { return .jd }
        }
        return .none
    }
    
    /// 根据链接返回 toast 文案和跳转 action
    /// 所有跳转统一用 UIApplication.shared.open（App 或浏览器）
    static func toastInfo(for link: String) -> (message: String, action: (() -> Void)?) {
        let target = detectApp(in: link)
        
        // 识别到电商平台，检查是否安装了对应 App
        if target != .none,
           let schemeURL = URL(string: target.scheme),
           UIApplication.shared.canOpenURL(schemeURL) {
            return ("点击跳转到\(target.appName) App", { UIApplication.shared.open(schemeURL) })
        }
        
        // 未安装 App 或非电商链接，用系统浏览器打开
        if let url = URL(string: link), url.scheme?.hasPrefix("http") == true {
            return ("点击在浏览器中打开", { UIApplication.shared.open(url) })
        }
        
        return ("已复制到剪贴板", nil)
    }
}
