-- ============================================================
-- Shared borders and backgrounds
-- ============================================================
--
-- Draws solid colors and simple borders for the shared AWP widgets.

local NS = _G.AzerothWaypointNS

local UIStyle = NS.UIStyle or {}
NS.UIStyle = UIStyle

function UIStyle.SetColorTexture(texture, color)
    if texture and type(texture.SetColorTexture) == "function" and type(color) == "table" then
        texture:SetColorTexture(color[1] or 0, color[2] or 0, color[3] or 0, color[4] or 1)
    end
end

function UIStyle.AddSimpleBorder(parent)
    if not parent then return end
    if parent._awpSimpleBorder then return parent._awpSimpleBorder end

    local function border(pointA, pointB, isHorizontal, r, g, b, a)
        local tex = parent:CreateTexture(nil, "BORDER")
        tex:SetPoint(pointA, parent, pointA, 0, 0)
        tex:SetPoint(pointB, parent, pointB, 0, 0)
        tex:SetColorTexture(r, g, b, a)
        if isHorizontal then
            tex:SetHeight(1)
        else
            tex:SetWidth(1)
        end
        return tex
    end

    parent._awpSimpleBorder = {
        border("TOPLEFT", "TOPRIGHT", true, 0.62, 0.45, 0.18, 0.78),
        border("BOTTOMLEFT", "BOTTOMRIGHT", true, 0.62, 0.45, 0.18, 0.70),
        border("TOPLEFT", "BOTTOMLEFT", false, 0.62, 0.45, 0.18, 0.70),
        border("TOPRIGHT", "BOTTOMRIGHT", false, 0.62, 0.45, 0.18, 0.70),
    }
    return parent._awpSimpleBorder
end
