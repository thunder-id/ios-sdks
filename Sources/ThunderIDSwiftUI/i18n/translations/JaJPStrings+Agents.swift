// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

extension JaJPStrings {
    /// The ja-JP strings of the personal agent components and the personal agent additions to the admin
    /// agent components.
    static let agents: [String: String] = [
        "user.agents.title": "個人用エージェント",
        "user.agents.description": "あなたの代わりにのみ動作するエージェントです。",
        "user.agents.list.columns.name": "名前",
        "user.agents.list.columns.status": "ステータス",
        "user.agents.list.empty": "個人用エージェントはありません。",
        "user.agents.list.error": "エージェントを読み込めませんでした。もう一度お試しください。",
        "user.agents.suspend_all.action": "すべて停止",
        "user.agents.suspend_all.confirm": "すべての個人用エージェントを停止しますか?停止を解除するまでアクセスできなくなります。",
        "user.agents.suspend_all.done": "停止したエージェント: {count}",
        "user.agents.details.overview": "概要",
        "user.agents.details.attributes": "属性",
        "user.agents.details.client_id": "クライアントID",
        "user.agents.details.grant_types": "グラントタイプ",
        "user.agents.details.redirect_uris": "リダイレクトURI",
        "user.agents.details.none": "なし",
        "user.agents.details.error": "このエージェントを読み込めませんでした。もう一度お試しください。",
        "user.agents.suspension.owner": "あなたがこのエージェントを停止しました。",
        "user.agents.suspension.organization": "組織がこのエージェントを停止しました。この停止を解除できるのは管理者のみです。",
        "user.agents.suspension.cascade": "アカウントが停止されている間、このエージェントは停止されたままです。",
        "user.agents.suspend.action": "停止",
        "user.agents.suspend.confirm": "{name} を停止しますか?停止を解除するまでアクセスできなくなります。",
        "user.agents.unsuspend.action": "停止を解除",
        "user.agents.action.error": "操作を完了できませんでした。もう一度お試しください。",
        "user.agents.edit.action": "編集",
        "user.agents.actions.menu": "エージェントの操作",
        "user.agents.edit.title": "エージェントを編集",
        "user.agents.edit.save": "変更を保存",
        "user.agents.fields.name": "名前",
        "user.agents.fields.description": "説明",
        "user.agents.fields.redirect_uris_hint": "認可コードグラントに必要です。URIは1行に1つずつ入力してください。",
        "user.agents.grant_types.authorization_code": "認可コード",
        "user.agents.grant_types.ciba": "バックチャネル認証 (CIBA)",
        "user.agents.grant_types.refresh_token": "リフレッシュトークン",
        "user.agents.delete.action": "エージェントを削除",
        "user.agents.delete.confirm": "{name} を削除しますか?この操作は元に戻せません。",
        "admin.agents.kind.personal": "個人用",
        "admin.agents.details.kind": "種類",
        "admin.agents.details.suspension.title": "停止元",
        "admin.agents.details.suspension.organization": "組織",
        "admin.agents.details.suspension.owner": "所有者",
        "admin.agents.details.suspension.cascade": "所有者のアカウント停止"
    ]
}
