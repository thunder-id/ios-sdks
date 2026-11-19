// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

extension TaINStrings {
    /// The ta-IN strings of the personal agent components and the personal agent additions to the admin
    /// agent components.
    static let agents: [String: String] = [
        "user.agents.title": "தனிப்பட்ட முகவர்கள்",
        "user.agents.description": "உங்கள் சார்பாக மட்டுமே செயல்படும் முகவர்கள்.",
        "user.agents.list.columns.name": "பெயர்",
        "user.agents.list.columns.status": "நிலை",
        "user.agents.list.empty": "உங்களிடம் தனிப்பட்ட முகவர்கள் இல்லை.",
        "user.agents.list.error": "உங்கள் முகவர்களை ஏற்ற முடியவில்லை. மீண்டும் முயற்சிக்கவும்.",
        "user.agents.suspend_all.action": "அனைத்தையும் இடைநிறுத்து",
        "user.agents.suspend_all.confirm":
            "உங்கள் தனிப்பட்ட முகவர்கள் அனைத்தையும் இடைநிறுத்தவா? இடைநிறுத்தத்தை நீக்கும் வரை அவற்றுக்கு அணுகல் இருக்காது.",
        "user.agents.suspend_all.done": "இடைநிறுத்தப்பட்ட முகவர்கள்: {count}",
        "user.agents.details.overview": "மேலோட்டம்",
        "user.agents.details.attributes": "பண்புகள்",
        "user.agents.details.client_id": "கிளையன்ட் ID",
        "user.agents.details.grant_types": "வழங்கல் வகைகள்",
        "user.agents.details.redirect_uris": "திசைதிருப்பு URIகள்",
        "user.agents.details.none": "எதுவும் இல்லை",
        "user.agents.details.error": "இந்த முகவரை ஏற்ற முடியவில்லை. மீண்டும் முயற்சிக்கவும்.",
        "user.agents.suspension.owner": "நீங்கள் இந்த முகவரை இடைநிறுத்தியுள்ளீர்கள்.",
        "user.agents.suspension.organization":
            "உங்கள் நிறுவனம் இந்த முகவரை இடைநிறுத்தியுள்ளது. அந்த இடைநிறுத்தத்தை நிர்வாகி மட்டுமே நீக்க முடியும்.",
        "user.agents.suspension.cascade":
            "உங்கள் கணக்கு இடைநிறுத்தப்பட்டிருக்கும் வரை இந்த முகவர் இடைநிறுத்தப்பட்டிருக்கும்.",
        "user.agents.suspend.action": "இடைநிறுத்து",
        "user.agents.suspend.confirm": "{name} ஐ இடைநிறுத்தவா? இடைநிறுத்தத்தை நீக்கும் வரை அதற்கு அணுகல் இருக்காது.",
        "user.agents.unsuspend.action": "இடைநிறுத்தத்தை நீக்கு",
        "user.agents.action.error": "செயலை முடிக்க முடியவில்லை. மீண்டும் முயற்சிக்கவும்.",
        "user.agents.edit.action": "திருத்து",
        "user.agents.actions.menu": "முகவர் செயல்கள்",
        "user.agents.edit.title": "முகவரைத் திருத்து",
        "user.agents.edit.save": "மாற்றங்களைச் சேமி",
        "user.agents.fields.name": "பெயர்",
        "user.agents.fields.description": "விளக்கம்",
        "user.agents.fields.redirect_uris_hint":
            "அங்கீகாரக் குறியீடு வழங்கலுக்குத் தேவை. ஒரு வரிக்கு ஒரு URI ஐ உள்ளிடவும்.",
        "user.agents.grant_types.authorization_code": "அங்கீகாரக் குறியீடு",
        "user.agents.grant_types.ciba": "பின்தள அங்கீகாரம் (CIBA)",
        "user.agents.grant_types.refresh_token": "புதுப்பிப்பு டோக்கன்",
        "user.agents.delete.action": "முகவரை நீக்கு",
        "user.agents.delete.confirm": "{name} ஐ நீக்கவா? இதைத் திரும்பப் பெற முடியாது.",
        "admin.agents.kind.personal": "தனிப்பட்ட",
        "admin.agents.details.kind": "பிரிவு",
        "admin.agents.details.suspension.title": "இடைநிறுத்தியவர்",
        "admin.agents.details.suspension.organization": "நிறுவனம்",
        "admin.agents.details.suspension.owner": "உரிமையாளர்",
        "admin.agents.details.suspension.cascade": "உரிமையாளரின் கணக்கு இடைநிறுத்தம்"
    ]
}
