//
//  AvatarCache.swift
//  Yep
//
//  Created by NIX on 15/3/16.
//  Copyright (c) 2015年 Catch Inc. All rights reserved.
//

import UIKit
import RealmSwift

class AvatarCache {

    static let sharedInstance = AvatarCache()

    let cache = NSCache()
    //let cacheQueue = dispatch_queue_create("AvatarCacheQueue", DISPATCH_QUEUE_CONCURRENT)
    let cacheQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0)

//    func roundImageNamed(name: String, ofRadius radius: CGFloat) -> UIImage {
//        let roundImageKey = "round-\(name)-\(radius)"
//        
//        if let roundImage = cache.objectForKey(roundImageKey) as? UIImage {
//            return roundImage
//
//        } else {
//            if let image = UIImage(named: name) {
//
//                let roundImage = image.roundImageOfRadius(radius)
//
//                cache.setObject(roundImage, forKey: roundImageKey)
//
//                return roundImage
//            }
//        }
//
//        return defaultRoundAvatarOfRadius(radius)
//    }

    func defaultRoundAvatarOfRadius(radius: CGFloat) -> UIImage {
        let facelessRouncImageKey = "round-faceless-\(radius)"

        if let roundImage = cache.objectForKey(facelessRouncImageKey) as? UIImage {
            return roundImage

        } else {
            let image = UIImage(named: "default_avatar")! // NOTICE: we need default_avatar indeed

            let roundImage = image.roundImageOfRadius(radius).decodedImage()

            cache.setObject(roundImage, forKey: facelessRouncImageKey)
            
            return roundImage
        }
    }

//    func roundImageFromURL(url: NSURL, ofRadius radius: CGFloat, completion: (UIImage) -> ()) {
//        let roundImageKey = "round-\(url.hashValue)"
//
//        if let roundImage = cache.objectForKey(roundImageKey) as? UIImage {
//            completion(roundImage)
//
//        } else {
//            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
//                if let data = NSData(contentsOfURL: url) {
//                    let image = UIImage(data: data)!
//
//                    let roundImage = image.roundImageOfRadius(radius)
//
//                    self.cache.setObject(roundImage, forKey: roundImageKey)
//
//                    completion(roundImage)
//                }
//            }
//        }
//    }

    func avatarFromURL(url: NSURL, completion: (UIImage) -> ()) {

        completion(UIImage(named: "default_avatar")!)

        let normalImageKey = "normal-\(url.hashValue)"

        let avatarURLString = url.absoluteString!

        // 先看看缓存
        if let normalImage = cache.objectForKey(normalImageKey) as? UIImage {
            completion(normalImage)

        } else {
            dispatch_async(self.cacheQueue) {
                if
                    let avatar = avatarWithAvatarURLString(avatarURLString, inRealm: Realm()),
                    let avatarFileURL = NSFileManager.yepAvatarURLWithName(avatar.avatarFileName),
                    let image = UIImage(contentsOfFile: avatarFileURL.path!) {

                        let image = image.decodedImage()

                        self.cache.setObject(image, forKey: normalImageKey)

                        completion(image)

                } else {
                    // 没办法，下载吧

                    if let data = NSData(contentsOfURL: url), image = UIImage(data: data) {

                        let image = image.decodedImage()

                        // TODO 裁减 image

                        dispatch_async(dispatch_get_main_queue()) {

                            var avatar = avatarWithAvatarURLString(avatarURLString, inRealm: Realm())

                            if avatar == nil {
                                
                                let avatarFileName = NSUUID().UUIDString

                                if let avatarURL = NSFileManager.saveAvatarImage(image, withName: avatarFileName) {
                                    let realm = Realm()

                                    let newAvatar = Avatar()
                                    newAvatar.avatarURLString = avatarURLString
                                    newAvatar.avatarFileName = avatarFileName

                                    realm.write {
                                        realm.add(newAvatar)
                                    }
                                }
                            }
                        }
                        
                        self.cache.setObject(image, forKey: normalImageKey)
                        
                        completion(image)
                    }
                }
            }
        }
    }


    typealias Completion = UIImage -> Void

    struct AvatarCompletion {
        let avatarURLString: String
        let radius: CGFloat
        let completion: Completion

        var avatarKey: String {
            return "round-\(radius)-\(avatarURLString.hashValue)"
        }
    }

    private var avatarCompletions = [AvatarCompletion]()

    private func completeWithImage(image: UIImage, avatarURLString: String) {

        for avatarCompletion in avatarCompletions.filter({ $0.avatarURLString == avatarURLString }) {

            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0)) {
                let avatar = image.roundImageOfRadius(avatarCompletion.radius)

                self.cache.setObject(avatar, forKey: avatarCompletion.avatarKey)

                dispatch_async(dispatch_get_main_queue()) {
                    avatarCompletion.completion(avatar)
                }

                let realm = Realm()

                if let avatarObject = avatarWithAvatarURLString(avatarURLString, inRealm: realm) {
                    switch avatarCompletion.radius {
                    case YepConfig.ConversationCell.avatarSize * 0.5:
                        if avatarObject.roundMini.length == 0 {
                            realm.write {
                                avatarObject.roundMini = UIImageJPEGRepresentation(avatar, 0.9)
                            }
                        }
                    case YepConfig.chatCellAvatarSize() * 0.5:
                        if avatarObject.roundNano.length == 0 {
                            realm.write {
                                avatarObject.roundNano = UIImageJPEGRepresentation(avatar, 0.9)
                            }
                        }
                    default:
                        break
                    }
                }
            }
        }

        // 完成过的就不需要了
        avatarCompletions = avatarCompletions.filter({ $0.avatarURLString != avatarURLString })
    }


    func roundAvatarWithAvatarURLString(avatarURLString: String, withRadius radius: CGFloat, completion: (UIImage) -> ()) {

        completion(defaultRoundAvatarOfRadius(radius))

        if avatarURLString.isEmpty {
            return
        }

        if let url = NSURL(string: avatarURLString) {

            let avatarCompletion = AvatarCompletion(avatarURLString: avatarURLString, radius: radius, completion: completion)

            let avatarKey = avatarCompletion.avatarKey

            // 先看看缓存
            if let roundImage = cache.objectForKey(avatarKey) as? UIImage {
                completion(roundImage)

            } else {
                // NOTICE: 默认在主线程添加
                avatarCompletions.append(avatarCompletion)

                if avatarCompletions.filter({ $0.avatarURLString == avatarURLString }).count > 1 {
                    // 不用做事，等着具有同样 avatarURLString 的 avatarCompletion 帮忙完成

                } else {

                    // 再看看是否已有裁剪后的圆图

                    if let avatar = avatarWithAvatarURLString(avatarURLString, inRealm: Realm()) {

                        switch radius {
                        case YepConfig.ConversationCell.avatarSize * 0.5:
                            if avatar.roundMini.length > 0 {
                                if let image = UIImage(data: avatar.roundMini) {
                                    completeWithImage(image, avatarURLString: avatarURLString)
                                    return
                                }
                            }
                        case YepConfig.chatCellAvatarSize() * 0.5:
                            if avatar.roundNano.length > 0 {
                                if let image = UIImage(data: avatar.roundNano) {
                                    completeWithImage(image, avatarURLString: avatarURLString)
                                    return
                                }
                            }
                        default:
                            break
                        }
                    }
                    
                    // 只能原图出场

                    dispatch_async(self.cacheQueue) {

                        // 再看看是否已下载

                        if let avatar = avatarWithAvatarURLString(avatarURLString, inRealm: Realm()) {

                            if let
                                avatarFileURL = NSFileManager.yepAvatarURLWithName(avatar.avatarFileName),
                                avatarFilePath = avatarFileURL.path,
                                image = UIImage(contentsOfFile: avatarFilePath) {

                                    let image = image.decodedImage()

                                    // 因此，要在主线程完成，防止对比 avatarCompletions 时数量不对
                                    dispatch_async(dispatch_get_main_queue()) {
                                        self.completeWithImage(image, avatarURLString: avatarURLString)
                                    }

                                    return
                            }
                        }

                        // 没办法，下载吧
                        if let data = NSData(contentsOfURL: url), image = UIImage(data: data) {

                            let image = image.decodedImage()

                            // TODO 裁减 image

                            let realm = Realm()

                            var avatar = avatarWithAvatarURLString(avatarURLString, inRealm: Realm())

                            if avatar == nil {
                                let avatarFileName = NSUUID().UUIDString

                                if let avatarURL = NSFileManager.saveAvatarImage(image, withName: avatarFileName) {
                                    let newAvatar = Avatar()
                                    newAvatar.avatarURLString = avatarURLString
                                    newAvatar.avatarFileName = avatarFileName

                                    realm.write {
                                        realm.add(newAvatar)
                                    }

                                    if let user = userWithAvatarURLString(avatarURLString, inRealm: realm) {

                                        if let oldAvatar = user.avatar {
                                            NSFileManager.deleteAvatarImageWithName(oldAvatar.avatarFileName)

                                            realm.write {
                                                realm.delete(oldAvatar)
                                            }
                                        }

                                        realm.write {
                                            user.avatar = newAvatar
                                        }
                                    }
                                }
                            }

                            // 因此，要在主线程完成，防止对比 avatarCompletions 时数量不对
                            dispatch_async(dispatch_get_main_queue()) {
                                self.completeWithImage(image, avatarURLString: avatarURLString)
                            }

                        } else {
                            // 因此，要在主线程完成，防止对比 avatarCompletions 时数量不对
                            dispatch_async(dispatch_get_main_queue()) {
                                self.completeWithImage(self.defaultRoundAvatarOfRadius(radius), avatarURLString: avatarURLString)
                            }
                        }
                    }
                }
            }

        } else {
            completion(defaultRoundAvatarOfRadius(radius))
        }
    }


    func roundAvatarOfUser(user: User, withRadius radius: CGFloat, completion: (UIImage) -> ()) {

        completion(defaultRoundAvatarOfRadius(radius))

        // 为下面切换线程准备，Realm 不能跨线程访问
        let avatarURLString = user.avatarURLString
        let userID = user.userID

        if avatarURLString.isEmpty {
            return
        }

        if let url = NSURL(string: avatarURLString) {

            let avatarCompletion = AvatarCompletion(avatarURLString: avatarURLString, radius: radius, completion: completion)

            let avatarKey = avatarCompletion.avatarKey

            // 先看看缓存
            if let roundImage = cache.objectForKey(avatarKey) as? UIImage {
                completion(roundImage)

            } else {
                // NOTICE: 默认在主线程添加
                avatarCompletions.append(avatarCompletion)

                if avatarCompletions.filter({ $0.avatarURLString == avatarURLString }).count > 1 {
                    // 不用做事，等着具有同样 avatarURLString 的 avatarCompletion 帮忙完成

                } else {

                    // 再看看是否已有裁剪后的圆图

                    if let avatar = avatarWithAvatarURLString(avatarURLString, inRealm: Realm()) {

                        switch radius {
                        case YepConfig.ConversationCell.avatarSize * 0.5:
                            if avatar.roundMini.length > 0 {
                                if let image = UIImage(data: avatar.roundMini) {
                                    completeWithImage(image, avatarURLString: avatarURLString)
                                    return
                                }
                            }
                        case YepConfig.chatCellAvatarSize() * 0.5:
                            if avatar.roundNano.length > 0 {
                                if let image = UIImage(data: avatar.roundNano) {
                                    completeWithImage(image, avatarURLString: avatarURLString)
                                    return
                                }
                            }
                        default:
                            break
                        }
                    }

                    // 只能原图出场

                    let oldAvatarURLString = user.avatar?.avatarURLString

                    dispatch_async(self.cacheQueue) {

                        let realm = Realm()

                        // 再看看是否已下载
                        if let avatar = avatarWithAvatarURLString(avatarURLString, inRealm: realm) {

                            if let
                                avatarFileURL = NSFileManager.yepAvatarURLWithName(avatar.avatarFileName),
                                avatarFilePath = avatarFileURL.path,
                                image = UIImage(contentsOfFile: avatarFilePath) {

                                    let image = image.decodedImage()

                                    // 因此，要在主线程完成，防止对比 avatarCompletions 时数量不对
                                    dispatch_async(dispatch_get_main_queue()) {
                                        self.completeWithImage(image, avatarURLString: avatarURLString)
                                    }

                                    return
                            }

                        } else { // 换了 Avatar，删除旧的
                            if let
                                oldAvatarURLString = oldAvatarURLString,
                                avatar = avatarWithAvatarURLString(oldAvatarURLString, inRealm: realm) {

                                    NSFileManager.deleteAvatarImageWithName(avatar.avatarFileName)

                                    realm.write {
                                        realm.delete(avatar)
                                    }
                            }
                        }

                        // 没办法，下载吧
                        if let data = NSData(contentsOfURL: url), image = UIImage(data: data) {

                            let image = image.decodedImage()

                            // TODO: 裁减 image

                            let realm = Realm()

                            var avatar = avatarWithAvatarURLString(avatarURLString, inRealm: realm)

                            if avatar == nil {
                                let avatarFileName = NSUUID().UUIDString

                                if let avatarURL = NSFileManager.saveAvatarImage(image, withName: avatarFileName) {
                                    let newAvatar = Avatar()
                                    newAvatar.avatarURLString = avatarURLString
                                    newAvatar.avatarFileName = avatarFileName

                                    realm.write {
                                        realm.add(newAvatar)
                                    }

                                    avatar = newAvatar
                                }
                            }

                            if let avatar = avatar {
                                if let user = userWithUserID(userID, inRealm: realm) {
                                    realm.write {
                                        user.avatar = avatar
                                    }
                                }
                            }

                            // 因此，要在主线程完成，防止对比 avatarCompletions 时数量不对
                            dispatch_async(dispatch_get_main_queue()) {
                                self.completeWithImage(image, avatarURLString: avatarURLString)
                            }

                        } else {
                            // 因此，要在主线程完成，防止对比 avatarCompletions 时数量不对
                            dispatch_async(dispatch_get_main_queue()) {
                                self.completeWithImage(self.defaultRoundAvatarOfRadius(radius), avatarURLString: avatarURLString)
                            }
                        }
                    }
                }
            }

        } else {
            completion(defaultRoundAvatarOfRadius(radius))
        }
    }
}



