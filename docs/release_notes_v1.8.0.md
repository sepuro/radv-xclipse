# RADV Xclipse 540 Release v1.8.0-stable-fp16

**Target Hardware**: Samsung Exynos 1580 (`s5e8855`)  
**GPU Core**: Samsung Xclipse 540 (AMD RDNA 3 / `CHIP_ARIEL`)  
**Android Platform**: Android 14+ (NDK API 34, aarch64)  
**Compilation Profiles**: Release `-O2` with `-Db_lto=true` (`thin` LTO), `fp16+dotprod`

---

### Highlights & Changes in v1.8.0

1. **Consolidated Master Safe Patch (`patches/mesa/01-ariel-master-safe.patch`)**:
   - Single source of truth replacing fragmented legacy patches.
   - Enforces `RADEON_SURF_DISABLE_DCC | RADEON_SURF_SCANOUT | RADEON_SURF_MODE_LINEAR_ALIGNED` on all `AHardwareBuffer` and `wsi_legacy_scanout` images.
   - Enforces `RADEON_SURF_DISABLE_DCC` on all storage images (`VK_IMAGE_USAGE_STORAGE_BIT`).
   - SELinux fallback to direct `/dev/dri/renderD128` opening.
   - `RADV_DEBUG_NO_HIZ` permanently active on `CHIP_ARIEL` to prevent depth buffer corruption.
   - Combined Depth Cache Flush (`VOYAGERSW-1566`) preserving DB integrity through vendor-tested TS event synchronization.
   - Texture barrier invalidation (`INV_VCACHE | INV_L2`) on `VK_ACCESS_2_SHADER_SAMPLED_READ_BIT` eliminating flickering and black surfaces.
   - Automatic shader disk cache path redirection to `/data/data/<package_name>/cache`.

2. **Safe FP16 Mediump Lowering & Vectorization**:
   - Enforces `vectorize_vec2_16bit = true` for `MESA_SHADER_FRAGMENT` and `MESA_SHADER_COMPUTE`.
   - Safely executes `nir_lower_mediump_vars` strictly scoped to local temporary variables (`nir_var_function_temp | nir_var_shader_temp`) on Fragment and Compute stages.
   - Preserves Vertex / Geometry input/output precision to prevent screen-space clipping distortion.
   - Cleans redundant conversions via `nir_opt_algebraic` and `nir_opt_constant_folding`.

3. **Samsung sgpu Kernel libdrm Fixes**:
   - Integrated `01-libdrm-xclipse-mmr-cache.patch` and `01-libdrm-xclipse-sgpu.patch`.
   - Prevents unaligned MMIO register traps and symbol collision during power state changes.

4. **Sanitized CI/CD Toolchain**:
   - Compiler flags: `-O2 -march=armv8.2-a+dotprod+fp16 -fno-semantic-interposition -fomit-frame-pointer`.
   - ThinLTO enabled (`-Db_lto=true`, `-Db_lto_mode=thin`) for link-time devirtualization without code bloat.
   - Stripped AdrenoTools package output (`vulkan.radeon.so`).
