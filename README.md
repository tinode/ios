# Tinodios: Tinode Messaging Client for iOS

iOS client for [Tinode](https://github.com/tinode/chat) in Swift.

Status: work in progress.

The immediate goal is to have a basic end-to-end working application prototype that one will be able to install and use.

## Features

### Completed

* Login
* Register new accounts.
* View the list of active chats
* Send and receive plain text messages one-on-one or in group chats.
* In-app presence notifications.
* Unread message counters.
* Local data persistence.
* Transport Level Security - https/wss.
* Drafty: Markdown-style formatting of text, e.g. \*style\* → **style**.
* Viewing attachments and inline images.


### Does not work yet

* Start new chats.
* Edit chat parameters.
* Typing indicators.
* Delivery and received/read indicators for messages (little check marks in messages).
* Muting/un-muting conversations and other permission management.
* Invite contacts to the app by SMS or email.
* Editing of personal details.
* Push notifications.
* Attachments and inline images cannot be created yet.


## Dependencies

* https://github.com/stephencelis/SQLite.swift
* https://github.com/jrendel/SwiftKeychainWrapper
* https://github.com/tidwall/SwiftWebSocket

## Other

* Demo avatars and some other graphics are from https://www.pexels.com/ under [CC0](https://www.pexels.com/photo-license/) license.
* Some iOS icons are from https://icons8.com/ under [CC BY-ND 3.0](https://icons8.com/license) license.

## Screenshots
<img src="ios-chats.png" alt="App screenshot - chat list" width="207" /> <img src="ios-chat.png" alt="App screenshot - conversation" width="207" />
