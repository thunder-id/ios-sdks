// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

extension PtBRStrings {
    /// The pt-BR strings of the personal agent components and the personal agent additions to the admin
    /// agent components.
    static let agents: [String: String] = [
        "user.agents.title": "Agentes pessoais",
        "user.agents.description": "Agentes que agem somente em seu nome.",
        "user.agents.list.columns.name": "Nome",
        "user.agents.list.columns.status": "Status",
        "user.agents.list.empty": "Você não tem agentes pessoais.",
        "user.agents.list.error": "Não foi possível carregar seus agentes. Tente novamente.",
        "user.agents.suspend_all.action": "Suspender todos",
        "user.agents.suspend_all.confirm":
            "Suspender todos os seus agentes pessoais? Eles perdem o acesso até você remover a suspensão.",
        "user.agents.suspend_all.done": "Agentes suspensos: {count}",
        "user.agents.details.overview": "Visão geral",
        "user.agents.details.attributes": "Atributos",
        "user.agents.details.client_id": "ID do cliente",
        "user.agents.details.grant_types": "Tipos de concessão",
        "user.agents.details.redirect_uris": "URIs de redirecionamento",
        "user.agents.details.none": "Nenhum",
        "user.agents.details.error": "Não foi possível carregar este agente. Tente novamente.",
        "user.agents.suspension.owner": "Você suspendeu este agente.",
        "user.agents.suspension.organization":
            "Sua organização suspendeu este agente. Somente um administrador pode remover essa suspensão.",
        "user.agents.suspension.cascade": "Este agente fica suspenso enquanto sua conta estiver suspensa.",
        "user.agents.suspend.action": "Suspender",
        "user.agents.suspend.confirm": "Suspender {name}? Ele perde o acesso até você remover a suspensão.",
        "user.agents.unsuspend.action": "Remover suspensão",
        "user.agents.action.error": "Não foi possível concluir a ação. Tente novamente.",
        "user.agents.edit.action": "Editar",
        "user.agents.actions.menu": "Ações do agente",
        "user.agents.edit.title": "Editar agente",
        "user.agents.edit.save": "Salvar alterações",
        "user.agents.fields.name": "Nome",
        "user.agents.fields.description": "Descrição",
        "user.agents.fields.redirect_uris_hint":
            "Necessário para a concessão de código de autorização. Insira uma URI por linha.",
        "user.agents.grant_types.authorization_code": "Código de autorização",
        "user.agents.grant_types.ciba": "Autenticação por canal secundário (CIBA)",
        "user.agents.grant_types.refresh_token": "Token de atualização",
        "user.agents.delete.action": "Excluir agente",
        "user.agents.delete.confirm": "Excluir {name}? Esta ação não pode ser desfeita.",
        "admin.agents.kind.personal": "Pessoal",
        "admin.agents.details.kind": "Categoria",
        "admin.agents.details.suspension.title": "Suspenso por",
        "admin.agents.details.suspension.organization": "Organização",
        "admin.agents.details.suspension.owner": "Responsável",
        "admin.agents.details.suspension.cascade": "Suspensão da conta do responsável"
    ]
}
