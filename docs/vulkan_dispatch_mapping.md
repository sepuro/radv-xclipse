# Mapeo y Grafo de Llamadas del Driver Vulkan Propietario (Samsung Exynos 1580 / Xclipse 540)

> **Documento Técnico de Ingeniería Inversa**: Resolución de funciones genéricas (`FUN_*` / `sub_*`) en el binario propietario `vulkan.samsung.so` (SoC `s5e8855`, GPU `CHIP_ARIEL`) mediante el análisis de la interfaz Vulkan HAL, el descifrado de la tabla de despacho `vkGetInstanceProcAddr`, y el trazado de aserciones hacia las funciones del subsistema AMD PAL / kernel `sgpu`.

---

## 1. Localización del Punto de Entrada del Driver (Android Vulkan HAL)

En el sistema Android, las bibliotecas Vulkan ICD no exportan individualmente todas las funciones de la API; en su lugar, exponen un descriptor de módulo de hardware (Android HAL Module):

- **Símbolo Exportado**: `HMI` (`hw_module_t`) en la dirección virtual **`0x2c923b8`**.
  - `id`: `"vulkan"` (`0x5055b8`)
  - `name`: `"SGPU Vulkan Driver"` (`0x4c622b`)
  - `author`: `"Samsung"` (`0x4c623e`)
  - `methods->open`: **`0x16c1880`** (`Samsung::Vulkan::OpenDevice`).

Al ser invocado por el cargador de Android (`libvulkan.so`), `open()` valida el nombre del dispositivo (`"vk0"`), registra en logcat bajo la etiqueta `[XGL]` y devuelve la estructura `hwvulkan_device_t` en la dirección **`0x2c924b0`**:
- `+0x40`: `EnumerateInstanceExtensionProperties` -> `0x1690f64`
- `+0x48`: `CreateInstance` -> `0x1690bc8` (despacha a `Instance::Create` en `0x168e990`)
- `+0x50`: `GetInstanceProcAddr` -> **`0x16705ac`**
- `common.close`: `0x16c18fc` (`Samsung::Vulkan::CloseDevice`)

---

## 2. El Mecanismo de Ofuscación XOR y la Tabla de Despacho

La función `vkGetInstanceProcAddr` en **`0x16705ac`** resuelve tanto funciones globales (`instance == NULL`) como funciones asociadas a la instancia o dispositivo (`instance != NULL`).

### Algoritmo de Descifrado de Cadenas Vulkan
Samsung ofuscó las cadenas literales de la API Vulkan mediante un cifrado XOR simétrico usando una clave fija de 6 bytes:
- **Clave Cifrada**: `"c!pH3r"` (ubicada en VA `0x4ee66f`).
- **Lógica de Comparación (Desensamblado en `0x16705fc` - `0x1670628`)**:
  ```c
  // x14 = puntero al arreglo de bytes cifrados
  // x16 = puntero a la cadena clave "c!pH3r"
  // x17 = puntero al nombre solicitado (pName)
  uint8_t enc_byte = *x14++;
  uint8_t key_byte = "c!pH3r"[char_idx % 6];
  uint8_t dec_char = enc_byte ^ key_byte;
  if (dec_char != *pName++) {
      // No coincide, avanzar a la siguiente entrada
      break;
  }
  ```

### Tablas de Despacho Maestras
1. **Arreglo de Punteros de Cadenas Cifradas**: **`0x2c59f80`** (contiene 522 punteros a las cadenas cifradas en `.rodata`).
2. **Tabla Maestra de Punteros de Función**: **`0x2b91980`** (4,176 bytes = 522 entradas × 8 bytes).
   - Copiada durante la inicialización de la instancia hacia el búfer de despacho dinámico mediante `memcpy(dest, 0x2b91980, 0x1050)` (desensamblado en `0x1663aec`).

---

## 3. Diccionario Completo de Puntos de Entrada Clave (512 Funciones Resueltas)

A continuación se detallan las direcciones virtuales reales de las funciones que en los desensambladores aparecen como `FUN_016*` o `sub_16*`:

| Índice | Nombre de la Función Vulkan | VA en `vulkan.samsung.so` | Rol en la Arquitectura |
| :---: | :--- | :---: | :--- |
| **0** | `vkGetInstanceProcAddr` | `0x16705ac` | Despacho de API de instancia |
| **1** | `vkCreateInstance` | `0x16707f4` | Creación de plataforma PAL |
| **5** | `vkGetDeviceProcAddr` | `0x1690bb0` | Despacho de funciones de dispositivo |
| **8** | `vkAllocateMemory` | `0x16794dc` | Alocación en `Pal::GpuMemory` / GEM |
| **9** | `vkBeginCommandBuffer` | `0x1609e0c` | Apertura de búfer de comandos PAL |
| **10** | `vkBindBufferMemory` | `0x16797b8` | Mapeo de memoria virtual GPU a búfer |
| **11** | `vkBindImageMemory` | `0x1679808` | Mapeo de memoria virtual GPU a imagen |
| **12** | `vkCmdBeginRenderPass` | `0x160ab5c` | Inicio de render pass y setup de DB/CB |
| **14** | `vkCmdBindDescriptorSets` | `0x160a088` | Configuración de User Data Registers |
| **15** | `vkCmdBindIndexBuffer` | `0x160a1e0` | Carga de registros de índice PM4 |
| **16** | `vkCmdBindPipeline` | `0x160a22c` | Activación de estados de pipeline |
| **27** | `vkCmdDraw` | `0x1609fdc` | Emisión de paquetes PM4 DRAW_INDEX_AUTO |
| **28** | `vkCmdDrawIndexed` | `0x160a004` | Emisión de paquetes PM4 DRAW_INDEX_2 |
| **45** | `vkCmdDispatch` | `0x160a9fc` | Emisión de paquetes PM4 DISPATCH_DIRECT |
| **52** | `vkCmdPipelineBarrier` | `0x160a898` | Sincronización y vaciado de caché |
| **74** | `vkCreateComputePipelines` | `0x1660230` | Compilación SC / LLPC para cómputo |
| **77** | `vkCreateDevice` | `0x1660740` | Inicialización de `Pal::Mgfx::Device` |
| **81** | `vkCreateGraphicsPipelines`| `0x1660314` | Compilación SC / LLPC para gráficos |
| **116** | `vkDeviceWaitIdle` | `0x1671348` | Espera de drenado de colas GPU |
| **182** | `vkQueueSubmit` | `0x160bb54` | Envío de CS al kernel `sgpu` |
| **183** | `vkQueueWaitIdle` | `0x160bdf0` | Sincronización de semáforo de cola |
| **347** | `vkCmdPipelineBarrier2` | `0x16a1060` | Sincronización extendida Vulkan 1.3 |
| **350** | `vkQueueSubmit2` | `0x160b02c` | Envío extendido de colas Vulkan 1.3 |
| **443** | `vkCmdDrawMeshTasksEXT` | `0x16a4d70` | Shaders de malla (NGG / Task / Mesh) |
| **492** | `vkCmdDispatchInterleavedSEC` | `0x16a7e10` | Extensión propietaria Samsung Cómputo |

> El mapeo completo de los 512 puntos de entrada en formato estructurado se encuentra en el archivo [`docs/vulkan_symbol_map.json`](file:///data/data/com.termux/files/home/xclipse540-driver-workspace/docs/vulkan_symbol_map.json).

---

## 4. Cadenas de Depuración y Fuentes C++ Leakeadas

Se extrajeron más de 200 referencias a rutas de código fuente C++ contenidas en macros de aserción (`assert`) y cadenas de log en `.rodata`:

### Arquitectura XGL (AMD ICD Core)
- `../../../drivers/xgl/icd/api/entry.cpp`: Generación de puntos de entrada ICD y estadísticas (`"appCacheHitRate: %0.1f%% (%d/%d)..."`).
- `../../../drivers/xgl/icd/api/vk_device.cpp`: Manejo de límites y versiones CTS (`"Override cts conformance version: %d.%d.%d.%d"`).
- `../../../drivers/xgl/icd/api/vk_cmdbuffer.cpp`: Tablas internas de pixel shaders (`"_amdgpu_ps_shdr_intrl_tbl"`, `"ERROR: %s invalid parameters"`).
- `../../../drivers/xgl/icd/api/vk_image.cpp` y `vk_fence.cpp`: Manejo de primitivas y sincronización nativa Android.

### Arquitectura PAL (Platform Abstraction Library - Mobile GFX)
- `mgfxDevice.cpp`: Implementación específica para Samsung Xclipse (MGFX).
  - `"Failed to create queueContext for queueType %d (%s:%d:%s)"`
  - `"could not initialize gpu-memory object. (%s:%d:%s)"`
- `linuxDevice.cpp`: Capa del sistema operativo Linux para SGPU.
  - `"Unknown Samsung GPU"`
  - `"virtual Pal::Linux::OsGpuMemory::~OsGpuMemory()"`
- `hwComputePipeline.cpp`: Configuración de registros de hardware RDNA 3 para pipelines de cómputo.

---

## 5. Grafo de Llamadas hacia las Funciones Reales de Hardware

### 5.1 Flujo de Envío de Comandos (`vkQueueSubmit`)
```
vkQueueSubmit (VA 0x160bb54)
    │
    ├── str w2, [x8, #0x108c]       (Guarda número de buffers de comandos)
    └── b 0x16476f0                  (Queue::Submit)
            │
            └── Pal::Queue::Submit()
                    │
                    └── amdgpu_cs_submit_raw()
                            │
                            └── ioctl(fd, DRM_AMDGPU_CS [0x44], &cs_args)
```

### 5.2 Flujo de Barreras y Vaciado de Caché (`VOYAGERSW-1566`)
```
vkCmdPipelineBarrier (VA 0x160a898) / vkCmdPipelineBarrier2 (VA 0x16a1060)
    │
    ├── Evaluación de srcStageMask y dstStageMask
    └── Pal::CmdBuffer::Barrier()
            │
            └── Workaround VOYAGERSW-1566 (Chip ARIEL):
                    ├── Emite paquete EVENT_WRITE (CACHE_FLUSH_AND_INV_TS_EVENT)
                    └── Emite paquete RELEASE_MEM forzando sincronización de CB y DB
```

### 5.3 Flujo de Alocación de Memoria (`vkAllocateMemory`)
```
vkAllocateMemory (VA 0x16794dc)
    │
    └── Device::AllocateMemory()
            │
            └── Pal::Linux::OsGpuMemory::Allocate()
                    │
                    ├── Caso 1: Importación AHardwareBuffer
                    │     ├── AHardwareBuffer_getNativeHandle()
                    │     └── Asignación de VA con RADV_XCLIPSE_VA_MTYPE_DEFAULT (is_local = true)
                    │
                    └── Caso 2: Memoria local de dispositivo
                          └── ioctl(fd, 0xc018649b, &gem_args) (Opcode 0x5b personalizado de Samsung)
```

---

## 6. Script de Renombrado Automático para Ghidra / IDA Pro

Para aplicar estos nombres automáticamente en la herramienta de ingeniería inversa, use el script disponible en [`scripts/rename_xgl_symbols.py`](file:///data/data/com.termux/files/home/xclipse540-driver-workspace/scripts/rename_xgl_symbols.py) o ejecute el siguiente fragmento en la consola de Python de Ghidra o IDA Pro:

```python
# Script para IDA Pro / Ghidra
import json

MAP_PATH = "docs/vulkan_symbol_map.json"
with open(MAP_PATH, "r") as f:
    symbols = json.load(f)

for sym in symbols:
    if sym["func_va"]:
        ea = int(sym["func_va"], 16)
        name = sym["name"]
        
        # Para IDA Pro:
        # idc.set_name(ea, name, idc.SN_CHECK)
        
        # Para Ghidra:
        # addr = currentAddress.getAddress(hex(ea))
        # createFunction(addr, name)
        print(f"Renombrado 0x{ea:x} -> {name}")
```
