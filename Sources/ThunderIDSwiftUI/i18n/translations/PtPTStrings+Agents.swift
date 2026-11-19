// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

extension PtPTStrings {
    /// The pt-PT strings of the personal agent components and the personal agent additions to the admin
    /// agent components.
    static let agents: [String: String] = [
        "user.agents.title": "Agentes pessoais",
        "user.agents.description": "Agentes que agem apenas em seu nome.",
        "user.agents.list.columns.name": "Nome",
        "user.agents.list.columns.status": "Estado",
        "user.agents.list.empty": "Não tem agentes pessoais.",
        "user.agents.list.error": "Não foi possível carregar os seus agentes. Tente novamente.",
        "user.agents.suspend_all.action": "Suspender todos",
        "user.agents.suspend_all.confirm":
            "Suspender todos os seus agentes pessoais? Perdem o acesso até levantar a suspensão.",
        "user.agents.suspend_all.done": "Agentes suspensos: {count}",
        "user.agents.details.overview": "Vista geral",
        "user.agents.details.attributes": "Atributos",
        "user.agents.details.client_id": "ID de cliente",
        "user.agents.details.grant_types": "Tipos de concessão",
        "user.agents.details.redirect_uris": "URIs de redirecionamento",
        "user.agents.details.none": "Nenhum",
        "user.agents.details.error": "Não foi possível carregar este agente. Tente novamente.",
        "user.agents.suspension.owner": "Suspendeu este agente.",
        "user.agents.suspension.organization":
            "A sua organização suspendeu este agente. Só um administrador pode levantar essa suspensão.",
        "user.agents.suspension.cascade": "Este agente fica suspenso enquanto a sua conta estiver suspensa.",
        "user.agents.suspend.action": "Suspender",
        "user.agents.suspend.confirm": "Suspender {name}? Perde o acesso até levantar a suspensão.",
        "user.agents.unsuspend.action": "Levantar suspensão",
        "user.agents.action.error": "Não foi possível concluir a ação. Tente novamente.",
        "user.agents.edit.action": "Editar",
        "user.agents.actions.menu": "Ações do agente",
        "user.agents.edit.title": "Editar agente",
        "user.agents.edit.save": "Guardar alterações",
        "user.agents.fields.name": "Nome",
        "user.agents.fields.description": "Descrição",
        "user.agents.fields.redirect_uris_hint":
            "Necessário para a concessão de código de autorização. Introduza um URI por linha.",
        "user.agents.grant_types.authorization_code": "Código de autorização",
        "user.agents.grant_types.ciba": "Autenticação por canal secundário (CIBA)",
        "user.agents.grant_types.refresh_token": "Token de atualização",
        "user.agents.delete.action": "Eliminar agente",
        "user.agents.delete.confirm": "Eliminar {name}? Esta ação não pode ser anulada.",
        "admin.agents.kind.personal": "Pessoal",
        "admin.agents.details.kind": "Categoria",
        "admin.agents.details.suspension.title": "Suspenso por",
        "admin.agents.details.suspension.organization": "Organização",
        "admin.agents.details.suspension.owner": "Responsável",
        "admin.agents.details.suspension.cascade": "Suspensão da conta do responsável"
    ]
}
