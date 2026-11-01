// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design internal header
// See Vtb_adder.h for the primary calling header

#ifndef VERILATED_VTB_ADDER___024ROOT_H_
#define VERILATED_VTB_ADDER___024ROOT_H_  // guard

#include "verilated.h"
#include "verilated_timing.h"


class Vtb_adder__Syms;

class alignas(VL_CACHE_LINE_BYTES) Vtb_adder___024root final {
  public:

    // DESIGN SPECIFIC STATE
    CData/*3:0*/ tb_adder__DOT__a;
    CData/*3:0*/ tb_adder__DOT__b;
    IData/*31:0*/ __Vi;
    VlUnpacked<QData/*63:0*/, 1> __VstlTriggered;
    VlUnpacked<QData/*63:0*/, 1> __VicoTriggered;
    VlUnpacked<QData/*63:0*/, 1> __VactTriggered;
    VlUnpacked<QData/*63:0*/, 1> __VactTriggeredAcc;
    VlUnpacked<QData/*63:0*/, 1> __VnbaTriggered;
    VlDelayScheduler __VdlySched;

    // INTERNAL VARIABLES
    Vtb_adder__Syms* vlSymsp;
    const char* vlNamep;

    // CONSTRUCTORS
    Vtb_adder___024root(Vtb_adder__Syms* symsp, const char* namep);
    ~Vtb_adder___024root();
    VL_UNCOPYABLE(Vtb_adder___024root);

    // INTERNAL METHODS
    void __Vconfigure(bool first);
};


#endif  // guard
