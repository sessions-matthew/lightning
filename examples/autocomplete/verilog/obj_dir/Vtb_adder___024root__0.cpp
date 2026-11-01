// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design implementation internals
// See Vtb_adder.h for the primary calling header

#include "Vtb_adder__pch.h"

VlCoroutine Vtb_adder___024root___eval_initial__TOP__Vtiming__0(Vtb_adder___024root* vlSelf);

void Vtb_adder___024root___eval_initial(Vtb_adder___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_adder___024root___eval_initial\n"); );
    Vtb_adder__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    Vtb_adder___024root___eval_initial__TOP__Vtiming__0(vlSelf);
}

void Vtb_adder___024root___eval_sample(Vtb_adder___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_adder___024root___eval_sample\n"); );
    Vtb_adder__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
}

#ifdef VL_DEBUG
VL_ATTR_COLD void Vtb_adder___024root___dump_triggers__ico(const VlUnpacked<QData/*63:0*/, 1> &triggers, const std::string &tag);
#endif  // VL_DEBUG

bool Vtb_adder___024root___eval_ico(Vtb_adder___024root* vlSelf, CData/*0:0*/ firstIteration) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_adder___024root___eval_ico\n"); );
    Vtb_adder__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    vlSelfRef.__VicoTriggered[0U] = ((0xfffffffffffffffeULL 
                                      & vlSelfRef.__VicoTriggered[0U]) 
                                     | (IData)((IData)(firstIteration)));
#ifdef VL_DEBUG
    if (VL_UNLIKELY(vlSymsp->_vm_contextp__->debug())) {
        Vtb_adder___024root___dump_triggers__ico(vlSelfRef.__VicoTriggered, "ico"s);
    }
#endif
    return (0U);
}

void Vtb_adder___024root___trigger_orInto__act_vec_vec(VlUnpacked<QData/*63:0*/, 1> &out, const VlUnpacked<QData/*63:0*/, 1> &in);
#ifdef VL_DEBUG
VL_ATTR_COLD void Vtb_adder___024root___dump_triggers__act(const VlUnpacked<QData/*63:0*/, 1> &triggers, const std::string &tag);
#endif  // VL_DEBUG
bool Vtb_adder___024root___trigger_anySet__act(const VlUnpacked<QData/*63:0*/, 1> &in);

bool Vtb_adder___024root___eval_act(Vtb_adder___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_adder___024root___eval_act\n"); );
    Vtb_adder__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Locals
    CData/*0:0*/ __VactExecute;
    // Body
    {
        // Inlined CFunc: _eval_triggers_vec__act
        vlSelfRef.__VactTriggered[0U] = (QData)((IData)(vlSelfRef.__VdlySched.awaitingCurrentTime()));
    }
    Vtb_adder___024root___trigger_orInto__act_vec_vec(vlSelfRef.__VactTriggered, vlSelfRef.__VactTriggeredAcc);
#ifdef VL_DEBUG
    if (VL_UNLIKELY(vlSymsp->_vm_contextp__->debug())) {
        Vtb_adder___024root___dump_triggers__act(vlSelfRef.__VactTriggered, "act"s);
    }
#endif
    Vtb_adder___024root___trigger_orInto__act_vec_vec(vlSelfRef.__VnbaTriggered, vlSelfRef.__VactTriggered);
    __VactExecute = Vtb_adder___024root___trigger_anySet__act(vlSelfRef.__VactTriggered);
    if (__VactExecute) {
        vlSelfRef.__VactTriggeredAcc.fill(0ULL);
        {
            // Inlined CFunc: _timing_resume
            if ((1ULL & vlSelfRef.__VactTriggered[0U])) {
                vlSelfRef.__VdlySched.resume();
            }
        }
    }
    return (__VactExecute);
}

bool Vtb_adder___024root___eval_inact(Vtb_adder___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_adder___024root___eval_inact\n"); );
    Vtb_adder__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Locals
    CData/*0:0*/ __VinactExecute;
    // Body
    __VinactExecute = vlSelfRef.__VdlySched.awaitingZeroDelay();
    if (__VinactExecute) {
        VL_FATAL_MT("tb_adder.sv", 3, "", "ZERODLY: Design Verilated with '--no-sched-zero-delay', but #0 delay executed at runtime");
    }
    return (__VinactExecute);
}

void Vtb_adder___024root___trigger_clear__act(VlUnpacked<QData/*63:0*/, 1> &out);

bool Vtb_adder___024root___eval_nba(Vtb_adder___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_adder___024root___eval_nba\n"); );
    Vtb_adder__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Locals
    CData/*0:0*/ __VnbaExecute;
    // Body
    __VnbaExecute = Vtb_adder___024root___trigger_anySet__act(vlSelfRef.__VnbaTriggered);
    if (__VnbaExecute) {
        Vtb_adder___024root___trigger_clear__act(vlSelfRef.__VnbaTriggered);
    }
    return (__VnbaExecute);
}

bool Vtb_adder___024root___eval_obs(Vtb_adder___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_adder___024root___eval_obs\n"); );
    Vtb_adder__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    return (0U);
}

bool Vtb_adder___024root___eval_react(Vtb_adder___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_adder___024root___eval_react\n"); );
    Vtb_adder__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    return (0U);
}

void Vtb_adder___024root___eval_postponed(Vtb_adder___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_adder___024root___eval_postponed\n"); );
    Vtb_adder__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
}

VlCoroutine Vtb_adder___024root___eval_initial__TOP__Vtiming__0(Vtb_adder___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_adder___024root___eval_initial__TOP__Vtiming__0\n"); );
    Vtb_adder__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    vlSymsp->_vm_contextp__->dumpfile("sim.vcd"s);
    vlSymsp->_traceDumpOpen();
    vlSelfRef.tb_adder__DOT__a = 0U;
    vlSelfRef.tb_adder__DOT__b = 0U;
    co_await vlSelfRef.__VdlySched.delay(0x000000000000000aULL, 
                                         nullptr, "tb_adder.sv", 
                                         20);
    vlSelfRef.tb_adder__DOT__a = 1U;
    vlSelfRef.tb_adder__DOT__b = 1U;
    co_await vlSelfRef.__VdlySched.delay(0x000000000000000aULL, 
                                         nullptr, "tb_adder.sv", 
                                         23);
    vlSelfRef.tb_adder__DOT__a = 2U;
    vlSelfRef.tb_adder__DOT__b = 3U;
    co_await vlSelfRef.__VdlySched.delay(0x000000000000000aULL, 
                                         nullptr, "tb_adder.sv", 
                                         26);
    vlSelfRef.tb_adder__DOT__a = 4U;
    vlSelfRef.tb_adder__DOT__b = 5U;
    co_await vlSelfRef.__VdlySched.delay(0x000000000000000aULL, 
                                         nullptr, "tb_adder.sv", 
                                         29);
    vlSelfRef.tb_adder__DOT__a = 8U;
    vlSelfRef.tb_adder__DOT__b = 9U;
    VL_WRITEF_NX("test completed\n",0);
    co_await vlSelfRef.__VdlySched.delay(0x0000000000000064ULL, 
                                         nullptr, "tb_adder.sv", 
                                         33);
    VL_FINISH_MT("tb_adder.sv", 34, "");
    co_return;
}

bool Vtb_adder___024root___trigger_anySet__ico(const VlUnpacked<QData/*63:0*/, 1> &in) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_adder___024root___trigger_anySet__ico\n"); );
    // Locals
    IData/*31:0*/ n;
    // Body
    n = 0U;
    do {
        if (in[n]) {
            return (1U);
        }
        n = ((IData)(1U) + n);
    } while ((1U > n));
    return (0U);
}

bool Vtb_adder___024root___trigger_anySet__act(const VlUnpacked<QData/*63:0*/, 1> &in) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_adder___024root___trigger_anySet__act\n"); );
    // Locals
    IData/*31:0*/ n;
    // Body
    n = 0U;
    do {
        if (in[n]) {
            return (1U);
        }
        n = ((IData)(1U) + n);
    } while ((1U > n));
    return (0U);
}

void Vtb_adder___024root___trigger_orInto__act_vec_vec(VlUnpacked<QData/*63:0*/, 1> &out, const VlUnpacked<QData/*63:0*/, 1> &in) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_adder___024root___trigger_orInto__act_vec_vec\n"); );
    // Locals
    IData/*31:0*/ n;
    // Body
    n = 0U;
    do {
        out[n] = (out[n] | in[n]);
        n = ((IData)(1U) + n);
    } while ((0U >= n));
}

void Vtb_adder___024root___trigger_clear__act(VlUnpacked<QData/*63:0*/, 1> &out) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_adder___024root___trigger_clear__act\n"); );
    // Locals
    IData/*31:0*/ n;
    // Body
    n = 0U;
    do {
        out[n] = 0ULL;
        n = ((IData)(1U) + n);
    } while ((1U > n));
}

#ifdef VL_DEBUG
void Vtb_adder___024root___eval_debug_assertions(Vtb_adder___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_adder___024root___eval_debug_assertions\n"); );
    Vtb_adder__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
}
#endif  // VL_DEBUG
