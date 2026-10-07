import Foundation

DistributedNotificationCenter.default().postNotificationName(
    NSNotification.Name("com.mumblr.toggle"),
    object: nil,
    userInfo: nil,
    deliverImmediately: true
)
DistributedNotificationCenter.default().postNotificationName(
    NSNotification.Name("com.parakeetflow.toggle"),
    object: nil,
    userInfo: nil,
    deliverImmediately: true
)
