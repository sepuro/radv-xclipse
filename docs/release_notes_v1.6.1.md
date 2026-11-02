# Custom RADV Vulkan Driver for Samsung Xclipse 540 (Exynos 1580)
## Release v1.6.1-displayfix (Clean Single-Patch Architecture & libdrm sgpu Fix)

Esta versión **v1.6.1-displayfix** resuelve de forma definitiva el problema de pantalla negra en el Exynos 1580 (`s5e8855` / `CHIP_ARIEL`) unificando la base de parches, incorporando el soporte de `libdrm` para el kernel `sgpu` de Samsung, y eliminando optimizaciones agresivas del compilador Clang que corrompían el renderizado.

---

### 🛠️ Correcciones Principales en este Release (v1.6.1-displayfix):

1. **Parche de `libdrm` para el Kernel `sgpu` de Samsung (`patches/libdrm/01-libdrm-xclipse-sgpu.patch`)**:
   - Resuelve el fallo silencioso en el Exynos 1580 donde la lectura de registros MMIO (`0x263e` / `GB_ADDR_CONFIG`) fallaba durante transiciones de energía de `sgpu.ko`.
   - Incorpora aislamiento de símbolos para `handle_table` evitando conflictos de enlace estático con Mesa.
   - Integración automática en el paso de preparación de GitHub Actions y en `subprojects/libdrm.wrap`.

2. **Unificación de Parches de Mesa en una Sola Fuente de Verdad (`patches/mesa/01-ariel-display-and-sgpu-fix.patch`)**:
   - Eliminados todos los parches fragmentados (01 al 08) que se pisaban entre sí.
   - Un solo parche limpio de 52 KB que consolida todas las adaptaciones para `CHIP_ARIEL` (WSI, AHB, SurfaceFlinger scanout, SELinux renderD128 fallback, GCR_CNTL cache invalidation, Wave32 unificado, GPL, y redirección de caché a `/data/data/<pkg>/cache`).

3. **Garantía de Video en Android SurfaceFlinger (`radv_image.c`)**:
   - Activación conjunta de `RADEON_SURF_DISABLE_DCC | RADEON_SURF_SCANOUT | RADEON_SURF_MODE_LINEAR_ALIGNED` para todas las imágenes de `AHardwareBuffer` y `wsi_legacy_scanout`.

4. **Desactivación de Optimizaciones Agresivas del Compilador**:
   - Revertidas banderas como `-ffast-math`, `-fno-semantic-interposition`, `-Db_lto_mode=thin` y vectorización agresiva en el workflow de CI.
   - Compilación con `-O2` estándar y `-Db_lto=false` para descartar cualquier corrupción de código generado en NIR y ACO.

5. **Estabilidad del Pipeline de Shading**:
   - Eliminado cualquier forzado global de VRS (`force_vrs`), manteniendo la extensión `VK_KHR_fragment_shading_rate` para uso bajo demanda.
   - Preservado `RADV_DEBUG_NO_HIZ` activo por defecto para `CHIP_ARIEL`.
   - Preservados los tiempos de espera originales en `drmSyncobjWait`.

---

### 📦 Archivos Distribuidos en este Release:
- **`Custom_RADV_Xclipse540.zip`**: Driver compilado y empaquetado para AdrenoTools.
- **`patches/mesa/01-ariel-display-and-sgpu-fix.patch`**: Parche único consolidado para Mesa RADV.
- **`patches/libdrm/01-libdrm-xclipse-sgpu.patch`**: Parche de compatibilidad `libdrm` para kernel `sgpu`.
