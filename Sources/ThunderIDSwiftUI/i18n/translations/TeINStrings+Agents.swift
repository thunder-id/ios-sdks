// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

extension TeINStrings {
    /// The te-IN strings of the personal agent components and the personal agent additions to the admin
    /// agent components.
    static let agents: [String: String] = [
        "user.agents.title": "వ్యక్తిగత ఏజెంట్లు",
        "user.agents.description": "మీ తరపున మాత్రమే పనిచేసే ఏజెంట్లు.",
        "user.agents.list.columns.name": "పేరు",
        "user.agents.list.columns.status": "స్థితి",
        "user.agents.list.empty": "మీకు వ్యక్తిగత ఏజెంట్లు ఏవీ లేవు.",
        "user.agents.list.error": "మీ ఏజెంట్లను లోడ్ చేయడం సాధ్యం కాలేదు. దయచేసి మళ్లీ ప్రయత్నించండి.",
        "user.agents.suspend_all.action": "అన్నింటినీ నిలిపివేయి",
        "user.agents.suspend_all.confirm":
            "మీ వ్యక్తిగత ఏజెంట్లన్నింటినీ నిలిపివేయాలా? మీరు నిలిపివేతను తొలగించే వరకు వాటికి యాక్సెస్ ఉండదు.",
        "user.agents.suspend_all.done": "నిలిపివేసిన ఏజెంట్లు: {count}",
        "user.agents.details.overview": "అవలోకనం",
        "user.agents.details.attributes": "లక్షణాలు",
        "user.agents.details.client_id": "క్లయింట్ ID",
        "user.agents.details.grant_types": "గ్రాంట్ రకాలు",
        "user.agents.details.redirect_uris": "రీడైరెక్ట్ URIలు",
        "user.agents.details.none": "ఏదీ లేదు",
        "user.agents.details.error": "ఈ ఏజెంట్\u{200C}ను లోడ్ చేయడం సాధ్యం కాలేదు. దయచేసి మళ్లీ ప్రయత్నించండి.",
        "user.agents.suspension.owner": "మీరు ఈ ఏజెంట్\u{200C}ను నిలిపివేశారు.",
        "user.agents.suspension.organization":
            "మీ సంస్థ ఈ ఏజెంట్\u{200C}ను నిలిపివేసింది. ఆ నిలిపివేతను నిర్వాహకుడు మాత్రమే తొలగించగలరు.",
        "user.agents.suspension.cascade": "మీ ఖాతా నిలిపివేయబడి ఉన్నంత వరకు ఈ ఏజెంట్ నిలిపివేయబడి ఉంటుంది.",
        "user.agents.suspend.action": "నిలిపివేయి",
        "user.agents.suspend.confirm": "{name} ను నిలిపివేయాలా? మీరు నిలిపివేతను తొలగించే వరకు దానికి యాక్సెస్ ఉండదు.",
        "user.agents.unsuspend.action": "నిలిపివేతను తొలగించు",
        "user.agents.action.error": "చర్యను పూర్తి చేయడం సాధ్యం కాలేదు. దయచేసి మళ్లీ ప్రయత్నించండి.",
        "user.agents.edit.action": "సవరించు",
        "user.agents.actions.menu": "ఏజెంట్ చర్యలు",
        "user.agents.edit.title": "ఏజెంట్\u{200C}ను సవరించు",
        "user.agents.edit.save": "మార్పులను సేవ్ చేయి",
        "user.agents.fields.name": "పేరు",
        "user.agents.fields.description": "వివరణ",
        "user.agents.fields.redirect_uris_hint": "ఆథరైజేషన్ కోడ్ గ్రాంట్\u{200C}కు అవసరం. ఒక్కో పంక్తికి ఒక URI నమోదు చేయండి.",
        "user.agents.grant_types.authorization_code": "ఆథరైజేషన్ కోడ్",
        "user.agents.grant_types.ciba": "బ్యాక్\u{200C}చానెల్ ప్రామాణీకరణ (CIBA)",
        "user.agents.grant_types.refresh_token": "రిఫ్రెష్ టోకెన్",
        "user.agents.delete.action": "ఏజెంట్\u{200C}ను తొలగించు",
        "user.agents.delete.confirm": "{name} ను తొలగించాలా? దీన్ని రద్దు చేయడం సాధ్యం కాదు.",
        "admin.agents.kind.personal": "వ్యక్తిగత",
        "admin.agents.details.kind": "వర్గం",
        "admin.agents.details.suspension.title": "నిలిపివేసినవారు",
        "admin.agents.details.suspension.organization": "సంస్థ",
        "admin.agents.details.suspension.owner": "యజమాని",
        "admin.agents.details.suspension.cascade": "యజమాని ఖాతా నిలిపివేత"
    ]
}
