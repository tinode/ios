# ios
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

Currently, the following tasks are in flight:
* Local data persistence: the messages in chat as well as other data (topics, subscriptions, etc.) are stored in a SQLite db after they are received from the server. This way the UI can fetch them from the db instead of going to the server.
* App UI:
  * chat/contacts view: after you log in, the app takes you to the list of your chats/contacts view (this is what this view looks like in Tindroid: https://github.com/tinode/tindroid/blob/master/android-contacts-1.png).
  * message view: When you click on a chat in the chat/contacts view, it should take you to the messages view for that chat (e.g. https://github.com/tinode/tindroid/blob/master/android-chat-1.png).

This is the skeleton functionality that one should be able to build more features around.

The end goal would be feature parity with the Tindroid (Tinode Android) App:
* Send and receive messages one-on-one or in group chats.
* Register new accounts.
* Start new chats.
* Edit chat parameters.
* In-app presence notifications.
* Unread message counters.
* Typing indicators.
* Push notifications.
* Indicators for messages received/read (little check marks in messages).
* Drafty: Markdown-style formatting of text, e.g. *styled* → styled. Implemented as spannable.
* Attachments and inline images.
* Muting/un-muting conversations and other permission management.
* Integration with Android's stock Contacts.
* Invite contacts to the app by SMS or email.
* Transport Level Security - https/wss.
* Offline mode is mostly functional.
* Editing of personal details.
