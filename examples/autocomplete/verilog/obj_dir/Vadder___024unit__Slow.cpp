// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design implementation internals
// See Vadder.h for the primary calling header

#include "Vadder__pch.h"

void Vadder___024unit___ctor_var_reset(Vadder___024unit* vlSelf);

Vadder___024unit::Vadder___024unit() = default;
Vadder___024unit::~Vadder___024unit() = default;

void Vadder___024unit::ctor(Vadder__Syms* symsp, const char* namep) {
    vlSymsp = symsp;
    vlNamep = strdup(Verilated::catName(vlSymsp->name(), namep));
    // Reset structure values
    Vadder___024unit___ctor_var_reset(this);
}

void Vadder___024unit::__Vconfigure(bool first) {
    (void)first;  // Prevent unused variable warning
}

void Vadder___024unit::dtor() {
    VL_DO_DANGLING(std::free(const_cast<char*>(vlNamep)), vlNamep);
}
