# Update Help and settings images

Use the [Help Image Capture Plan](Help-Image-Capture-Plan.md) for the capture checklist, approved names, captions, and asset inventory.

1. Crop a real client screenshot and save the game texture under `media/help/`. Record the crop's dimensions.
2. In [Help](help_pages.lua), use `Capture("Name", width, height, caption)` with the asset basename and proportional display dimensions. Use `Row` to group related captures.
3. In the [settings catalog](../interface/options/canvas_data.lua), use the explicit `.tga` path for a TGA preview. Update `PREVIEW_IMAGE_SIZES` and the corresponding preview entry together.
4. Reload the client and check Help and the settings preview at normal and narrow widths. Export a separate readable PNG for web use.
