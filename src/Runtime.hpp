#pragma once
#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace glow {
struct Vec3 { float x,y,z; };
struct Bounds { Vec3 center, extents; };
struct Target { float x,y,w,h,distance; };
class Runtime {
public:
    bool attach();
    void sample(float width,float height,std::vector<Target>& result);
    void setTint(bool enabled);
    void setVisualsAllowed(bool allowed);
    void restore();
    std::string diagnosticRoots();
    std::string diagnosticNode(int id);
    std::string status="Waiting for Unity";
private:
    void* library=nullptr;
    void* bindings=nullptr;
    void* unityObject=nullptr;
    void* component=nullptr;
    void* cameraClass=nullptr;
    void* rendererClass=nullptr;
    void* materialClass=nullptr;
    bool tint=false;
    bool visualsAllowed=false;
    double lastTint=0;
    struct Saved { uint32_t renderer,materials; std::vector<uint32_t> clones; };
    std::vector<Saved> saved;
    std::vector<uint32_t> diagnosticHandles;
    int diagnosticID(void* object);
    void* find(const char* ns,const char* name);
    const void* method(void* klass,const char* name,const std::vector<std::string>& parameters);
    void* call(void* klass,const char* name,void* instance,const std::vector<std::string>& types={},void** args=nullptr);
    void* objectCall(void* obj,const char* name,const std::vector<std::string>& types={},void** args=nullptr);
    bool alive(void* object);
    size_t length(void* array);
    void* element(void* array,size_t index);
    void applyTint(void* binding);
};
}
