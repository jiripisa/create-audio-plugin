// ParamTable.cpp - the whole parameter table of the {{APP}} engine, put together from the
// platform block and the instrument's tables: the amounts' names, the sections and the
// programs.

// A product and a sum stay two roundings. An optimised build would otherwise fuse them into one
// multiply-add where a debug build does not, and the two builds would render different last
// bits: the engine's sound must be the same in both, and the same as the references it is
// tested against.
#pragma clang fp contract(off)

#include "ParamTable.h"

#include <cstdio>

namespace {{APP_LOWER}} {

namespace {

Param amount(const char* id, const char* name)
{
    return Param{ id, name, "%", {{APP_UPPER}}_KIND_FLOAT, -100.0f, 100.0f, 0.0f, false, 0 };
}

// The amounts take their names from their knob. No amount is on at rest: the instrument comes
// plain and the player or a program sets the movement.
char amountIds[kNumLfoAmounts + kNumVelAmounts][32], amountNames[kNumLfoAmounts + kNumVelAmounts][48];

const Param* makeParams()
{
    static Param table[kNumParams];
    for (int i = 0; i < kNumKnobs; ++i) table[i] = knob(i);
    for (int lfo = 0; lfo < kNumLfos; ++lfo)
        for (int t = 0; t < kNumLfoTargets; ++t)
        {
            const int slot = lfo * kNumLfoTargets + t;
            std::snprintf(amountIds[slot], sizeof amountIds[slot], "lfo%d%s", lfo + 1, knob(kLfoTargets[t]).id);
            std::snprintf(amountNames[slot], sizeof amountNames[slot], "LFO %d>%s", lfo + 1, knob(kLfoTargets[t]).name);
            table[kNumKnobs + slot] = amount(amountIds[slot], amountNames[slot]);
        }
    for (int t = 0; t < kNumVelTargets; ++t)
    {
        const int slot = kNumLfoAmounts + t;
        std::snprintf(amountIds[slot], sizeof amountIds[slot], "vel%s", knob(kVelTargets[t]).id);
        std::snprintf(amountNames[slot], sizeof amountNames[slot], "VEL>%s", knob(kVelTargets[t]).name);
        table[kNumKnobs + slot] = amount(amountIds[slot], amountNames[slot]);
    }
    return table;
}

} // namespace

const Param& param(int index)
{
    static const Param* const table = makeParams();
    return table[index];
}

const char* choiceName(int index, int choice)
{
    if (!validParam(index)) return "";
    const Param& p = param(index);
    if (p.kind != {{APP_UPPER}}_KIND_CHOICE || !p.choices) return "";
    return p.choices[std::clamp(choice, 0, (int)p.max)];
}

const std::vector<Section>& sections()
{
    static const std::vector<Section> table = [] {
        std::vector<Section> all;
        for (const SectionDef& def : kSections)
        {
            Section s{ def.name, {} };
            for (int p : def.knobs)
            {
                if (p < kNumPlatformKnobs) break;
                s.params.push_back(p);
            }
            all.push_back(s);
        }
        Section master{ "Master", {} };
        for (int p = 0; p < kNumPlatformKnobs; ++p) master.params.push_back(p);
        all.push_back(master);
        return all;
    }();
    return table;
}

int sectionOf(int param)
{
    for (size_t s = 0; s < sections().size(); ++s)
        for (int p : sections()[s].params) if (p == param) return (int)s;
    return -1;
}

const std::vector<Program>& programs()
{
    static const std::vector<Program> table = [] {
        std::vector<Program> all;
        for (const ProgramDef& def : kPrograms)
        {
            Program p;
            p.name = def.name;
            for (int i = 0; i < kNumParams; ++i) p.values[i] = param(i).def;
            for (const Override& o : def.overrides) if (validParam(o.param)) p.values[o.param] = o.value;
            all.push_back(p);
        }
        return all;
    }();
    return table;
}

bool programSets(int param) { return param != kOctave; }

} // namespace {{APP_LOWER}}
