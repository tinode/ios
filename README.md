# Tinodios: Tinode Messaging Client for iOS

iOS client for [Tinode](https://github.com/tinode/chat) in Swift.

Status: beta. Usable and mostly stable but bugs may happen.

<a href="https://apps.apple.com/us/app/tinode/id1483763538"><img src="app-store.svg" height=36></a>

## Installing and running

This is NOT a standalone app, this is just a frontend, a client. It requires a [backend](https://github.com/tinode/chat/). See [installation instructions](https://github.com/tinode/chat/blob/master/INSTALL.md).

## Getting support

* Read [server-side](https://github.com/tinode/chat/blob/master/docs/API.md) API documentation.
* For support, general questions, discussions post to [https://groups.google.com/d/forum/tinode](https://groups.google.com/d/forum/tinode).
* For bugs and feature requests [open an issue](https://github.com/tinode/ios/issues/new).

## Features

### Completed

* Login
* Register new accounts.
* Start new chats.
* Edit personal details.
* Edit chat parameters.
* View the list of active chats
* Send and receive plain text messages one-on-one or in group chats.
* In-app presence notifications.
* Unread message counters.
* Local data persistence.
* Transport Level Security - https/wss.
* Drafty: Markdown-style formatting of text, e.g. \*style\* → **style**.
* Viewing attachments and inline images.
* Delivery and received/read indicators for messages (little check marks in messages).
* Muting/un-muting conversations and other permission management.
* Invite contacts to the app by SMS or email.
* Push notifications.
* Attachments and inline images.

### Not Done Yet

* Previews not generated for videos, audio, links or docs.
* Typing indicators.
* No support for switching between multiple backends.
* Mentions, hashtags.
* Replying or forwarding messages.
* End-to-End encryption.

## Dependencies

### SDK

* https://github.com/tidwall/SwiftWebSocket for websocket support

### Application

* [SQLite.swift](https://github.com/stephencelis/SQLite.swift) for convenience of SQLite use.
* [SwiftKeychainWrapper](https://github.com/jrendel/SwiftKeychainWrapper) for convenience of Keychain access.
* [PhoneNumberKit](https://github.com/marmelroy/PhoneNumberKit) for normalizing phone numbers.
* [Kingfisher](https://github.com/onevcat/Kingfisher) for out-of-band image handling.
* Google Firebase for [push notifications](https://firebase.google.com/docs/cloud-messaging/ios/client), [analytics](https://firebase.google.com/docs/analytics/get-started?platform=ios), and [crash reporting](https://firebase.google.com/docs/crashlytics/get-started?platform=ios). See below.


## Push notifications

If you want to use the app with your own server and want push notification to work you have to set them up:

* Register at https://firebase.google.com/, [set up the project](https://firebase.google.com/docs/ios/setup) if you have not done so already.
* [Download your own](https://firebase.google.com/docs/cloud-messaging/ios/client) config file `GoogleService-Info.plist` and place it in the `Tinodios/` folder of your copy of the project. The config file contains keys specific to your Firebase/FCM registration.
* Copy Google-provided server key to `tinode.conf`, see details [here](https://github.com/tinode/chat/blob/master/docs/faq.md#q-what-are-the-options-for-enabling-push-notifications).

## Translations

The app is currently available in the following languages:
* English (default)
* Chinese (simplified)
* Chinese (traditional)
* Russian
* Spanish

More translations are welcome. See [instructions](https://github.com/tinode/chat/blob/devel/docs/translations.md#ios).

## Other

* Demo avatars and some other graphics are from https://www.pexels.com/ under [CC0](https://www.pexels.com/photo-license/) license.
* Some iOS icons are from https://icons8.com/ under [CC BY-ND 3.0](https://icons8.com/license) license.

## Screenshots
<img src="ios-chats.png" alt="App screenshot - chat list" width="207" /> <img src="ios-chat.png" alt="App screenshot - conversation" width="207" /> <img src="ios-acc-personal.png" alt="App screenshot - account settings" width="207" />
<img src="ios-topic-info.png" alt="App screenshot - topic info" width="207" /> <img src="ios-find-people.png" alt="App screenshot - find people" width="207" />
