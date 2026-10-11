import CNCKit
import Foundation

/// Display names for the curated materials — one place for every picker.
extension CuttingMaterial {
    var title: LocalizedStringResource { titleResource }

    var titleResource: LocalizedStringResource {
        switch id {
        case "aluminum_6061": "Aluminum (6061)"
        case "copper": "Copper"
        case "brass": "Brass"
        case "mild_steel_1018": "Mild steel (1018)"
        case "stainless_303_304": "Stainless steel (303/304)"
        case "acrylic_cast": "Acrylic (cast)"
        case "hdpe_delrin": "HDPE / Delrin"
        case "polycarbonate": "Polycarbonate"
        case "abs": "ABS"
        case "nylon": "Nylon"
        case "pvc_foam": "PVC foam board"
        case "solid_surface": "Solid surface (Corian)"
        case "machinable_wax": "Machinable wax"
        case "fr4_pcb": "FR4 / PCB"
        case "carbon_fiber": "Carbon fiber / G10"
        case "foam_xps": "XPS foam"
        case "mdf": "MDF"
        case "plywood": "Plywood"
        case "hardwood": "Hardwood (oak, maple)"
        case "softwood": "Softwood (pine)"
        case "bamboo": "Bamboo"
        default: LocalizedStringResource(stringLiteral: id)
        }
    }
}
