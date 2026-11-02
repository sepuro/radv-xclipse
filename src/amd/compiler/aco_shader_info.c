/*
 * Copyright © 2026 Advanced Micro Devices, Inc. & Samsung Electronics
 * SPDX-License-Identifier: MIT
 */

#include "aco_shader_info.h"

/* Dynamic wave size selector for CHIP_ARIEL:
 * Allows using Wave32 by default to maximize SIMD occupancy on the dual-WGP
 * (4 CUs) configuration of the Samsung Xclipse 540 (Exynos 1580), while
 * switching dynamically to Wave64 on heavy compute shaders with extensive register usage.
 */
uint8_t
aco_compiler_ariel_select_wave_size(unsigned workgroup_size, unsigned shared_size,
                                    unsigned num_ubos, unsigned num_ssbos)
{
   if (workgroup_size >= 64 &&
       (shared_size >= 4096 || (num_ubos + num_ssbos) >= 4 || workgroup_size >= 256))
      return 64;

   return 32;
}
