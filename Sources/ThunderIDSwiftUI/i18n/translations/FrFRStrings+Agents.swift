// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

extension FrFRStrings {
    /// The fr-FR strings of the personal agent components and the personal agent additions to the admin
    /// agent components.
    static let agents: [String: String] = [
        "user.agents.title": "Agents personnels",
        "user.agents.description": "Agents qui agissent uniquement en votre nom.",
        "user.agents.list.columns.name": "Nom",
        "user.agents.list.columns.status": "Statut",
        "user.agents.list.empty": "Vous n'avez aucun agent personnel.",
        "user.agents.list.error": "Impossible de charger vos agents. Veuillez réessayer.",
        "user.agents.suspend_all.action": "Tout suspendre",
        "user.agents.suspend_all.confirm":
            "Suspendre tous vos agents personnels ? Ils perdent l'accès jusqu'à ce que vous leviez la suspension.",
        "user.agents.suspend_all.done": "Agents suspendus : {count}",
        "user.agents.details.overview": "Aperçu",
        "user.agents.details.attributes": "Attributs",
        "user.agents.details.client_id": "ID client",
        "user.agents.details.grant_types": "Types d'octroi",
        "user.agents.details.redirect_uris": "URI de redirection",
        "user.agents.details.none": "Aucun",
        "user.agents.details.error": "Impossible de charger cet agent. Veuillez réessayer.",
        "user.agents.suspension.owner": "Vous avez suspendu cet agent.",
        "user.agents.suspension.organization":
            "Votre organisation a suspendu cet agent. Seul un administrateur peut lever cette suspension.",
        "user.agents.suspension.cascade": "Cet agent reste suspendu tant que votre compte est suspendu.",
        "user.agents.suspend.action": "Suspendre",
        "user.agents.suspend.confirm": "Suspendre {name} ? Il perd l'accès jusqu'à ce que vous leviez la suspension.",
        "user.agents.unsuspend.action": "Lever la suspension",
        "user.agents.action.error": "L'action n'a pas pu être effectuée. Veuillez réessayer.",
        "user.agents.edit.action": "Modifier",
        "user.agents.actions.menu": "Actions de l'agent",
        "user.agents.edit.title": "Modifier l'agent",
        "user.agents.edit.save": "Enregistrer les modifications",
        "user.agents.fields.name": "Nom",
        "user.agents.fields.description": "Description",
        "user.agents.fields.redirect_uris_hint":
            "Nécessaire pour l'octroi par code d'autorisation. Saisissez un URI par ligne.",
        "user.agents.grant_types.authorization_code": "Code d'autorisation",
        "user.agents.grant_types.ciba": "Authentification par canal de retour (CIBA)",
        "user.agents.grant_types.refresh_token": "Jeton de rafraîchissement",
        "user.agents.delete.action": "Supprimer l'agent",
        "user.agents.delete.confirm": "Supprimer {name} ? Cette action est irréversible.",
        "admin.agents.kind.personal": "Personnel",
        "admin.agents.details.kind": "Nature",
        "admin.agents.details.suspension.title": "Suspendu par",
        "admin.agents.details.suspension.organization": "Organisation",
        "admin.agents.details.suspension.owner": "Propriétaire",
        "admin.agents.details.suspension.cascade": "Suspension du compte du propriétaire"
    ]
}
