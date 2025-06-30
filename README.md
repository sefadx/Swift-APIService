# APIService for Swift Concurrency (async/await) 🚀

Centralized API handler with secure token-based authentication, auto-refresh mechanism, and built-in retry on token expiration.

## ✨ Features

* Modern async/await-based API requests
* AccessToken & RefreshToken management
* Automatic access token refresh on HTTP 401 errors
* UI feedback integration with `.loading`, `.popupInfo`, `.popupError` using a central `Router`
* Auto-refresh of refreshToken if less than 1 day is left
* Centralized token management via `TokenStorage`
* Generic response model: `BaseResponseModel<T>`

## 🛠️ APIService Usage

### GET Example

```swift
let res = try await APIService(token: TokenStorage.getToken(key: .accessToken))
    .get(.user(userId: "username"), responseType: BaseResponseModel<UserModel>.self)
```

### POST Example

```swift
let body = LoginRequest(email: "test@mail.com", password: "123456")
let res = try await APIService()
    .post(.login, body: body, responseType: BaseResponseModel<AuthTokenModel>.self)
```

### Automatic Retry on 401

If a request fails due to accessToken expiration, a new token is fetched and the original request is retried:

```swift
func fetchMe() async {
    Router.instance.push(.loading)
    defer { Router.instance.pop(.loading) }

    do {
        let res = try await APIService(token: TokenStorage.getToken(key: .accessToken))
            .get(.me, responseType: BaseResponseModel<UserModel>.self)
        if let data = res.data {
            self.me = data
        }
    } catch {
        Router.instance.replace(.popupInfo(model: .unknownProblem))
    }
}
```

## 🔒 Token Refresh Logic

* Each API call uses the accessToken from `TokenStorage`
* If the accessToken is expired (401), the APIService will automatically:

  * Use the refreshToken to get a new accessToken
  * Retry the original request
* If the refreshToken has less than 1 day left to expire, a new refreshToken is also issued

## 🧠 Architecture Overview

* `APIService`: Handles all network requests
* `TokenStorage`: Saves and retrieves tokens
* `Router`: Manages navigation and view stack
* `BaseResponseModel<T>`: Standard API response wrapper

## 📆 Requirements

* Swift 5.7+
* iOS 16+
* SwiftUI

## 📅 No Dependencies

Fully native and dependency-free. Plug-and-play in Swift projects.

## ✅ Tested On

* iOS 16+
* Xcode 15+
* Swift Concurrency environment

---

**Created by:** @sefadx
