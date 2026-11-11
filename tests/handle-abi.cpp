#include "../src/Runtime.hpp"
#include <type_traits>
#include <vector>
#include <cassert>
// Regression for the real-device fault: Unity 6000 GC handles are not uint32 IDs.
static_assert(std::is_pointer<glow::Handle>::value, "Il2CppGCHandle must use the Unity 6000 pointer ABI");
int main(){
    const uintptr_t bits=sizeof(void*)==8?uintptr_t(0x123456789abcdef0ULL):uintptr_t(0x12345678);
    glow::Handle handle=reinterpret_cast<void*>(bits);
    std::vector<glow::Handle> saved{handle};
    assert(reinterpret_cast<uintptr_t>(saved.front())==bits);
}
