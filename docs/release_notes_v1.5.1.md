# Custom RADV Vulkan Driver for Samsung Xclipse 540 (Exynos 1580)
## Release v1.5.1-hotfix (Linear Scanout & Safe Master Optimization)

Esta versión **v1.5.1-hotfix** corrige de manera definitiva la pantalla negra en el procesador Samsung Exynos 1580 (`s5e8855` / `CHIP_ARIEL`) restaurando la alineación lineal para Android SurfaceFlinger y eliminando el conflicto de Variable Rate Shading (VRS) global forzado.

---

### 🛠️ Correcciones Críticas en este Hotfix (v1.5.1):
1. **Restauración de `RADEON_SURF_MODE_LINEAR_ALIGNED` para Android AHB / Scanout (`radv_image.c`)**:
   - Para todas las imágenes con `VK_EXTERNAL_MEMORY_HANDLE_TYPE_ANDROID_HARDWARE_BUFFER_BIT_ANDROID` o `wsi_legacy_scanout`, se activan conjuntamente las tres banderas obligatorias:
     `RADEON_SURF_DISABLE_DCC | RADEON_SURF_SCANOUT | RADEON_SURF_MODE_LINEAR_ALIGNED`.
   - Esto garantiza que Android SurfaceFlinger / HWComposer interprete la memoria lineal sin corrupciones ni framebuffers en negro.

2. **Eliminación del VRS Global Forzado (`radv_device.c`)**:
   - Se removió la asignación forzada `device->force_vrs = RADV_FORCE_VRS_1x2` por defecto.
   - En hardware GFX11 (RDNA 3 / Xclipse 540), forzar VRS globalmente causaba conflictos con `RADV_DEBUG_NO_HIZ`, provocando fallos en el rasterizador de fragmentos.
   - La extensión `VK_KHR_fragment_shading_rate` permanece activa para ser utilizada por aplicaciones que la soliciten explícitamente.

3. **Optimizaciones de Rendimiento y Estabilidad Consolidadas**:
   - **Shader Disk Cache (`src/util/disk_cache.c`)**: Lectura de `/proc/self/cmdline` para redirigir la caché a `/data/data/<package_name>/cache`.
   - **Graphics Pipeline Library (GPL)**: Activación permanente con fast linking para eliminar tirones (*stutter*).
   - **Wave32 Unificado**: `ps_wave_size = 32`, `cs_wave_size = 32`, `ge_wave_size = 32`, `rt_wave_size = 32` y `use_ngg_culling = false` para maximizar la ocupación SIMD en los 2 WGPs / 4 CUs de la Xclipse 540.
   - **Invalidación Selectiva de Caché L2 / VCACHE (`radv_cmd_buffer.c`)**: Solo en transiciones de lectura de texturas tras operaciones de escritura, y *Combined Depth Cache Flush* restringido estrictamente a barreras Depth/Stencil.
   - **Caché de Búferes Staging (`radv_amdgpu_bo.c`)**: Retención durante 500 ms para minimizar llamadas repetitivas al kernel `sgpu`.

---

### 📦 Archivos Incluidos:
- **`Custom_RADV_Xclipse540.zip`**: Paquete listo para instalar en emuladores y apps compatibles con AdrenoTools (Mesa RADV optimizado para Cortex-A720 y Xclipse 540).
- **`08-ariel-safe-master-optimization.patch`**: Parche maestro limpio con las correcciones seguras aplicadas.
- **`01` a `07` (`.patch`)**: Parches acumulativos del árbol de desarrollo.
