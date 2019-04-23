# Tinodios

Experimental iOS client.

Status: work in progress.

Presently, Tinode iOS SDK can:
* Connect to Tinode server.
* Log into an account.
* Register new accounts.
* Subscribe to p2p topics.
* Publish/receive messages in p2p topics.
* Send/receive presence notifications.

The immediate goal is to have a basic end-to-end working application prototype that one will be able to install and use for the mentioned functionality.

This is the skeleton functionality that one should be able to build more features around.

## Features

### Completed
* View chats
* Send and receive plain text messages one-on-one or in group chats.
* Register new accounts.
* In-app presence notifications.
* Unread message counters.
* Local data persistence: the messages in chat as well as other data (topics, subscriptions, etc.) are stored in a SQLite db after they are received from the server. This way the UI can fetch them from the db instead of going to the server.

### In progress
* Start new chats.
* Edit chat parameters.
* Typing indicators.
* Indicators for messages received/read (little check marks in messages).
* Drafty: Markdown-style formatting of text, e.g. *styled* → styled. Implemented as spannable.
* Attachments and inline images.
* Muting/un-muting conversations and other permission management.
* Integration with iOS's stock Contacts.
* Invite contacts to the app by SMS or email.
* Transport Level Security - https/wss.
* Editing of personal details.
* Push notifications.


## Dependencies

* https://github.com/MessageKit
* https://github.com/MessageKit/MessageInputBar
* https://github.com/stephencelis/SQLite.swift
* https://github.com/jrendel/SwiftKeychainWrapper
* https://github.com/tidwall/SwiftWebSocket

## Other

Demo avatars and some other graphics are from https://www.pexels.com/ under [CC0 license](https://www.pexels.com/photo-license/).

Background patterns from http://subtlepatterns.com/, commercial and non-commercial use allowed with attribution.


## Screenshots
<img src="ios-chats.png" alt="App screenshot - chat list" width="207" />
<img src="ios-chat.png" alt="App screenshot - conversation" width="207" />
