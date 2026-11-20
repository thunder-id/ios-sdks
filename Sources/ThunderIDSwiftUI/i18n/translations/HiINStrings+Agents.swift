// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

extension HiINStrings {
    /// The hi-IN strings of the personal agent components and the personal agent additions to the admin
    /// agent components.
    static let agents: [String: String] = [
        "user.agents.title": "व्यक्तिगत एजेंट",
        "user.agents.description": "एजेंट जो केवल आपकी ओर से कार्य करते हैं।",
        "user.agents.list.columns.name": "नाम",
        "user.agents.list.columns.status": "स्थिति",
        "user.agents.list.empty": "आपके पास कोई व्यक्तिगत एजेंट नहीं है।",
        "user.agents.list.error": "आपके एजेंट लोड नहीं हो सके। कृपया पुनः प्रयास करें।",
        "user.agents.suspend_all.action": "सभी को निलंबित करें",
        "user.agents.suspend_all.confirm":
            "अपने सभी व्यक्तिगत एजेंट निलंबित करें? निलंबन हटाने तक उनकी पहुंच बंद रहेगी।",
        "user.agents.suspend_all.done": "निलंबित एजेंट: {count}",
        "user.agents.details.overview": "अवलोकन",
        "user.agents.details.attributes": "विशेषताएँ",
        "user.agents.details.client_id": "क्लाइंट ID",
        "user.agents.details.grant_types": "ग्रांट प्रकार",
        "user.agents.details.redirect_uris": "रीडायरेक्ट URI",
        "user.agents.details.none": "कोई नहीं",
        "user.agents.details.error": "यह एजेंट लोड नहीं हो सका। कृपया पुनः प्रयास करें।",
        "user.agents.suspension.owner": "आपने इस एजेंट को निलंबित किया है।",
        "user.agents.suspension.organization":
            "आपके संगठन ने इस एजेंट को निलंबित किया है। केवल व्यवस्थापक ही वह निलंबन हटा सकता है।",
        "user.agents.suspension.cascade": "जब तक आपका खाता निलंबित है, यह एजेंट निलंबित रहेगा।",
        "user.agents.suspend.action": "निलंबित करें",
        "user.agents.suspend.confirm": "{name} को निलंबित करें? निलंबन हटाने तक इसकी पहुंच बंद रहेगी।",
        "user.agents.unsuspend.action": "निलंबन हटाएं",
        "user.agents.action.error": "कार्रवाई पूरी नहीं हो सकी। कृपया पुनः प्रयास करें।",
        "user.agents.edit.action": "संपादित करें",
        "user.agents.actions.menu": "एजेंट की कार्रवाइयां",
        "user.agents.edit.title": "एजेंट संपादित करें",
        "user.agents.edit.save": "परिवर्तन सहेजें",
        "user.agents.fields.name": "नाम",
        "user.agents.fields.description": "विवरण",
        "user.agents.fields.redirect_uris_hint": "ऑथराइज़ेशन कोड ग्रांट के लिए आवश्यक। प्रति पंक्ति एक URI दर्ज करें।",
        "user.agents.grant_types.authorization_code": "ऑथराइज़ेशन कोड",
        "user.agents.grant_types.ciba": "बैकचैनल प्रमाणीकरण (CIBA)",
        "user.agents.grant_types.refresh_token": "रिफ्रेश टोकन",
        "user.agents.delete.action": "एजेंट हटाएं",
        "user.agents.delete.confirm": "{name} को हटाएं? इसे पूर्ववत नहीं किया जा सकता।",
        "admin.agents.kind.personal": "व्यक्तिगत",
        "admin.agents.details.kind": "श्रेणी",
        "admin.agents.details.suspension.title": "द्वारा निलंबित",
        "admin.agents.details.suspension.organization": "संगठन",
        "admin.agents.details.suspension.owner": "स्वामी",
        "admin.agents.details.suspension.cascade": "स्वामी के खाते का निलंबन"
    ]
}
