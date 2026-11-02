# Auditoría Técnica y Especificación de Correcciones: Texturas y Stuttering en Samsung Xclipse 540 (CHIP_ARIEL / Exynos 1580)

Este documento detalla los hallazgos de la auditoría de bajo nivel sobre el driver original de Samsung (`vulkan.s5e8855.so` / `sgpu.ko` en `ref_decompiled/`) y las soluciones implementadas en Mesa RADV para eliminar la corrupción de texturas y los micro-tirones (stuttering).

---

## 1. Auditoría de Formatos Comprimidos de Textura en `vkGetPhysicalDeviceFormatProperties2`

### 1.1 Decodificación Nativa por Hardware (Texture Sampling Unit)
La GPU Samsung Xclipse 540 (`CHIP_ARIEL`, microarquitectura AMD RDNA 3 personalizada por Samsung) incorpora decodificadores dedicados en silicio para los estándares de compresión del ecosistema móvil:

1. **ASTC 2D LDR (28 formatos contiguos)**:
   - Formatos: `VK_FORMAT_ASTC_4x4_UNORM_BLOCK` a `VK_FORMAT_ASTC_12x12_UNORM_BLOCK` y sus variantes `SRGB_BLOCK`.
   - Códigos T# en descriptor (Word 1 bits [27:20]):
     - **LDR UNORM**: Códigos `133` a `146` (`4x4`=133, `5x4`=134, `5x5`=135, `6x5`=136, `6x6`=137, `8x5`=138, `8x6`=139, `8x8`=140, `10x5`=141, `10x6`=142, `10x8`=143, `10x10`=144, `12x10`=145, `12x12`=146).
     - **LDR sRGB**: Códigos `161` a `174` siguiendo la misma secuencia de bloques.
   - **ASTC HDR (`ASTC_*_SFLOAT`)**: No posee soporte por silicio (`textureCompressionASTC_HDR = false`).

2. **ETC2 / EAC (10 formatos contiguos)**:
   - A diferencia de AMD RDNA estándar de escritorio (donde `has_etc_support = false`), el bloque de textura de Samsung implementa decodificadores directos:
     - `VK_FORMAT_ETC2_R8G8B8_UNORM_BLOCK` / `ETC1_RGB8`: **123**
     - `VK_FORMAT_ETC2_R8G8B8_SRGB_BLOCK`: **124**
     - `VK_FORMAT_ETC2_R8G8B8A8_UNORM_BLOCK`: **125**
     - `VK_FORMAT_ETC2_R8G8B8A8_SRGB_BLOCK`: **126**
     - `VK_FORMAT_EAC_R11_UNORM_BLOCK`: **127**
     - `VK_FORMAT_EAC_R11_SNORM_BLOCK`: **128**
     - `VK_FORMAT_EAC_R11G11_UNORM_BLOCK`: **129**
     - `VK_FORMAT_EAC_R11G11_SNORM_BLOCK`: **130**
     - `VK_FORMAT_ETC2_R8G8B8A1_UNORM_BLOCK`: **131**
     - `VK_FORMAT_ETC2_R8G8B8A1_SRGB_BLOCK`: **132**

3. **Formatos BC1, BC2, BC3**:
   - Soportados nativamente en hardware por el rasterizador y sampler de AMD RDNA 3 (`IMG_DATA_FORMAT_BC1`, `BC2`, `BC3`).

### 1.2 Formatos Emulados vía GPU Compute Shaders (BC4–BC7)
- `BC4_UNORM` -> Transcodificado a `VK_FORMAT_EAC_R11_UNORM_BLOCK` (o carrier `BC3`).
- `BC5_UNORM` -> Transcodificado a `VK_FORMAT_EAC_R11G11_UNORM_BLOCK`.
- `BC7_UNORM` -> Transcodificado hacia plano portador ASTC 4x4 (`a7_encode`) o `BC3` (`bc_bc3_encode`).
- `BC4/BC5_SNORM` -> Transcodificado a `VK_FORMAT_EAC_R11/R11G11_SNORM_BLOCK` o decodificado a `R8/RG8_SNORM`.
- `BC6H_UFLOAT` -> Re-codificado a `VK_FORMAT_B10G11R11_UFLOAT_PACK32` (o `RGBA16F`).
- `BC6H_SFLOAT` -> Decodificado a `VK_FORMAT_R16G16B16A16_SFLOAT`.

---

## 2. Invalidación de Caché en Transiciones de Texturas (`TRANSFER_DST` -> `SHADER_READ`)

En la microarquitectura GFX11 / RDNA 3, la invalidación de memorias intermedias se divide en:

### 2.1 Campos en `RELEASE_MEM` (`PKT3_RELEASE_MEM`)
- `S_491_GLV_INV(1)`: bit 14 (`0x00004000`) -> Invalida Vector Cache (L0 de textura).
- `S_491_GL1_INV(1)`: bit 15 (`0x00008000`) -> Invalida GL1 (L1 compartida de datos).
- `S_491_GL2_INV(1)`: bit 20 (`0x00100000`) -> Invalida L2 (GL2 unificada).
- `S_491_GL2_WB(1)`: bit 21 (`0x00200000`) -> Writeback de datos de L2 hacia DRAM.

### 2.2 Campos en `ACQUIRE_MEM` (`PKT3_ACQUIRE_MEM`)
- `S_587_GLI_INV(V_587_GLI_ALL)`: bits [1:0] = 0x2 -> Invalida caché de instrucciones.
- `S_587_GLV_INV(1)`: bit 8 (`0x00000100`) -> Invalida Vector Cache (L0 de muestreo).
- `S_587_GL1_INV(1)`: bit 9 (`0x00000200`) -> Invalida GL1.
- `S_587_GL2_INV(1)`: bit 14 (`0x00004000`) -> Invalida L2.
- `S_587_GL2_WB(1)`: bit 15 (`0x00008000`) -> Writeback de L2.

### 2.3 Causa de la Corrupción y Corrección
En Mesa RADV upstream, `can_skip_buffer_l2_flushes()` asume coherencia total entre CB/DMA y L2/TC en hardware GFX10+, omitiendo `AC_BARRIER_INV_L2` e `AC_BARRIER_INV_VMEM`. En el SoC Exynos 1580, el bus del sistema y los controladores de memoria no son snooped entre el motor de transferencia y las cachés de textura L0/L1/L2. Por tanto, toda transición desde `TRANSFER_WRITE` o `COLOR_ATTACHMENT_WRITE` hacia `SHADER_SAMPLED_READ` debe emitir de manera obligatoria:
- `AC_BARRIER_INV_VMEM` (fuerza `GLV_INV` y `GL1_INV`)
- `AC_BARRIER_INV_L2` (fuerza `GL2_INV` y `GL2_WB`)

---

## 3. Corrección de Descompresión DCC en Texturas de Almacenamiento y Copia CPU

En la Xclipse 540, el motor DCC (Delta Color Compression) produce corrupción de bloques si una textura con uso `STORAGE` o escrituras de transferencia frecuentes se lee a través del sampler sin descompresión completa.
**Solución**: Se desactiva DCC (`RADEON_SURF_DISABLE_DCC`) específicamente cuando:
- La imagen posee `VK_IMAGE_USAGE_STORAGE_BIT`
- La imagen posee `VK_IMAGE_USAGE_HOST_TRANSFER_BIT` o proviene de transferencias de staging desde CPU.

---

## 4. Eliminación de Micro-Tirones (Stuttering)

1. **Reutilización de Buffers de Staging en Winsys (`radv_amdgpu_bo.c`)**:
   - Se incrementa el pool de caché de BOs (`RADV_XCLIPSE_IBCACHE_BUCKETS`) de 64 a 256 buckets, y la capacidad (`RADV_XCLIPSE_IBCACHE_CAP`) de 64 MiB a 256 MiB.
   - Se permite cachear buffers accesibles por CPU (`RADEON_FLAG_CPU_ACCESS` en dominio GTT) hasta 16 MiB.
   - Cuando el juego sube texturas a la GPU (por ejemplo al rotar la cámara), el driver reutiliza BOs ya vinculados al GART en lugar de realizar llamadas costosas al kernel (`amdgpu_gem_create_ioctl` y `amdgpu_gem_va_ioctl`).

2. **Compilación Rápida de Shaders (GPL)**:
   - Se activa de forma predeterminada `VK_EXT_graphics_pipeline_library` (GPL) y `graphicsPipelineLibraryFastLinking`, permitiendo que DXVK, VKD3D y emuladores enlacen etapas de shader pre-compiladas instantáneamente sin congelar el hilo de renderizado.

3. **Restricción de VRS 1x2 al Framebuffer Principal**:
   - El forzado de `RADV_FORCE_VRS_1x2` se limita estrictamente al pase 3D del framebuffer principal con buffer de profundidad (`color_att_count == 1` con depth attachment), excluyendo texturas intermedias, pases G-Buffer, mapas de sombras y post-procesado para evitar borrosidad o distorsión.
