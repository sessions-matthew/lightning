// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design implementation internals
// See Vadder.h for the primary calling header

#include "Vadder__pch.h"

VL_ATTR_COLD void Vadder___024unit___ctor_var_reset(Vadder___024unit* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+      Vadder___024unit___ctor_var_reset\n"); );
    Vadder__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    vlSelf->__VmonitorNum = 0;
    vlSelf->__VmonitorOff = 0;
}
