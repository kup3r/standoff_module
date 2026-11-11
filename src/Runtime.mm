#include "Runtime.hpp"
#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <cmath>
#include <cstring>
#include <algorithm>
#include <chrono>
#include <cstdlib>

namespace glow {
// Exported IL2CPP API only; no MethodInfo or Il2CppClass memory layouts.
static void* (*domain_get)();
static void** (*domain_get_assemblies)(void*,size_t*);
static void* (*assembly_get_image)(void*);
static void* (*class_from_name)(void*,const char*,const char*);
static void* (*class_get_parent)(void*);
static bool (*class_is_assignable_from)(void*,void*);
static const void* (*class_get_methods)(void*,void**);
static const char* (*method_get_name)(const void*);
static uint32_t (*method_get_param_count)(const void*);
static const void* (*method_get_param)(const void*,uint32_t);
static char* (*type_get_name)(const void*);
static void (*ilfree)(void*);
static void* (*runtime_invoke)(const void*,void*,void**,void**);
static void* (*object_get_class)(void*);
static void* (*object_unbox)(void*);
static const void* (*class_get_type)(void*);
static void* (*type_get_object)(const void*);
static void* (*thread_current)();
static void* (*thread_attach)(void*);
static uintptr_t (*array_length)(void*);
static uint32_t (*array_object_header_size)();
static Handle (*gchandle_new)(void*,bool);
static void* (*gchandle_get_target)(Handle);
static void (*gchandle_free)(Handle);
static void* (*array_new)(void*,uintptr_t);
static void (*gc_wbarrier_set_field)(void*,void**,void*);
static void* (*object_new)(void*);
static void* (*string_new)(const char*);
static const char* (*class_get_name)(void*);
static const char* (*class_get_namespace)(void*);
static bool (*class_is_valuetype)(void*);
static uint32_t (*class_get_rank)(void*);
static void* (*class_get_fields)(void*,void**);
static const char* (*field_get_name)(void*);
static uint32_t (*field_get_flags)(void*);
static const void* (*field_get_type)(void*);
static void* (*field_get_value_object)(void*,void*);

template<class T> static bool value(void* boxed,T& out) {
    if(!boxed)return false;
    std::memcpy(&out,object_unbox(boxed),sizeof(T));return true;
}
static double now(){return std::chrono::duration<double>(std::chrono::steady_clock::now().time_since_epoch()).count();}
bool Runtime::attach() {
    if(library)return true;
    void* h=dlopen("@rpath/UnityFramework.framework/UnityFramework",RTLD_NOLOAD|RTLD_NOW);
    if(!h){status="UnityFramework has not loaded";return false;}
#define BIND(local,exported) local=reinterpret_cast<decltype(local)>(dlsym(h,"il2cpp_" exported)); if(!local){status="Missing IL2CPP API: " exported;dlclose(h);return false;}
    BIND(domain_get,"domain_get"); BIND(domain_get_assemblies,"domain_get_assemblies");
    BIND(assembly_get_image,"assembly_get_image");BIND(class_from_name,"class_from_name");
    BIND(class_get_parent,"class_get_parent");BIND(class_is_assignable_from,"class_is_assignable_from");
    BIND(class_get_methods,"class_get_methods");BIND(method_get_name,"method_get_name");
    BIND(method_get_param_count,"method_get_param_count");BIND(method_get_param,"method_get_param");
    BIND(type_get_name,"type_get_name");BIND(ilfree,"free");BIND(runtime_invoke,"runtime_invoke");
    BIND(object_get_class,"object_get_class");BIND(object_unbox,"object_unbox");
    BIND(class_get_type,"class_get_type");BIND(type_get_object,"type_get_object");
    BIND(thread_current,"thread_current");BIND(thread_attach,"thread_attach");
    BIND(array_length,"array_length");BIND(array_object_header_size,"array_object_header_size");
    BIND(gchandle_new,"gchandle_new");BIND(gchandle_get_target,"gchandle_get_target");BIND(gchandle_free,"gchandle_free");
    BIND(array_new,"array_new");BIND(gc_wbarrier_set_field,"gc_wbarrier_set_field");
    BIND(object_new,"object_new");BIND(string_new,"string_new");
    BIND(class_get_name,"class_get_name");BIND(class_get_namespace,"class_get_namespace");
    BIND(class_is_valuetype,"class_is_valuetype");BIND(class_get_rank,"class_get_rank");
    BIND(class_get_fields,"class_get_fields");BIND(field_get_name,"field_get_name");
    BIND(field_get_flags,"field_get_flags");BIND(field_get_type,"field_get_type");BIND(field_get_value_object,"field_get_value_object");
#undef BIND
    if(!domain_get()){status="IL2CPP domain not ready";dlclose(h);return false;}
    if(!thread_current())thread_attach(domain_get());
    // Only the arm64 reference-array ABI is used, checked before reading arrays.
    if(array_object_header_size()!=4*sizeof(void*)){status="Unsupported IL2CPP array ABI";dlclose(h);return false;}
    unityObject=find("UnityEngine","Object");component=find("UnityEngine","Component");
    cameraClass=find("UnityEngine","Camera");rendererClass=find("UnityEngine","Renderer");
    materialClass=find("UnityEngine","Material");
    bindings=find("Axlebolt.Standoff.Gameplay.Player","PlayerBindings");
    if(!unityObject||!component||!cameraClass||!rendererClass||!materialClass||!bindings){status="Required class not found in this build";dlclose(h);return false;}
    if(!class_is_assignable_from(component,bindings)){
        status="PlayerBindings is not a Component: game adapter requires mapping";dlclose(h);return false;
    }
    library=h;status="Adapter attached (unverified on device)";return true;
}
void* Runtime::find(const char* ns,const char* name){
    size_t count=0;auto assemblies=domain_get_assemblies(domain_get(),&count);
    if(count>4096)return nullptr;
    for(size_t i=0;i<count;i++)if(void* c=class_from_name(assembly_get_image(assemblies[i]),ns,name))return c;
    return nullptr;
}
const void* Runtime::method(void* c,const char* name,const std::vector<std::string>& params){
    for(int depth=0;c&&depth<64;c=class_get_parent(c),depth++){
        void* iter=nullptr;
        while(auto m=class_get_methods(c,&iter)){
            if(std::strcmp(method_get_name(m),name)||method_get_param_count(m)!=params.size())continue;
            bool match=true;
            for(size_t i=0;i<params.size();i++){char* n=type_get_name(method_get_param(m,(uint32_t)i));match&=n&&params[i]==n;if(n)ilfree(n);}
            if(match)return m;
        }
    }return nullptr;
}
void* Runtime::call(void* c,const char* name,void* instance,const std::vector<std::string>& types,void** args){
    auto m=method(c,name,types);if(!m){status=std::string("Missing method: ")+name;return nullptr;}
    void* exception=nullptr;void* r=runtime_invoke(m,instance,args,&exception);
    if(exception){status=std::string("Managed exception: ")+name;return nullptr;}return r;
}
void* Runtime::objectCall(void* obj,const char* name,const std::vector<std::string>& types,void** args){
    if(!obj)return nullptr;void* c=object_get_class(obj);
    return call(c,name,class_is_valuetype(c)?object_unbox(obj):obj,types,args);
}
bool Runtime::alive(void* obj){if(!obj)return false;void* args[]={obj};bool b=false;return value(call(unityObject,"op_Implicit",nullptr,{"UnityEngine.Object"},args),b)&&b;}
size_t Runtime::length(void* a){return a?array_length(a):0;}
void* Runtime::element(void* a,size_t i){return i<length(a)?reinterpret_cast<void**>(static_cast<char*>(a)+array_object_header_size())[i]:nullptr;}

void Runtime::sample(float width,float height,std::vector<Target>& result){
    result.clear();if(!visualsAllowed){status="Visual effects suspended";return;}if(!attach())return;
    void* cam=call(cameraClass,"get_main",nullptr);if(!alive(cam)){restore();status="No main camera";return;}
    int pw=0,ph=0;value(objectCall(cam,"get_pixelWidth"),pw);value(objectCall(cam,"get_pixelHeight"),ph);
    if(pw<=0||ph<=0)return;
    void* reflectionType=type_get_object(class_get_type(bindings));void* args[]={reflectionType};
    void* arr=call(unityObject,"FindObjectsOfType",nullptr,{"System.Type"},args);
    if(!arr){restore();return;}
    Handle root=gchandle_new(arr,false);
    bool refreshTint=tint&&now()-lastTint>2;
    if(refreshTint){restore();lastTint=now();}
    Vec3 cameraPosition{};void* tr=objectCall(cam,"get_transform");
    bool cameraPositionValid=value(objectCall(tr,"get_position"),cameraPosition);
    size_t count=std::min<size_t>(length(arr),64);
    for(size_t i=0;i<count;i++){
        void* binding=element(arr,i);if(!alive(binding))continue;
        void* collider=objectCall(binding,"get_CapsuleCollider");if(!alive(collider))continue;
        Bounds bounds{};if(!value(objectCall(collider,"get_bounds"),bounds))continue;
        if(!std::isfinite(bounds.extents.y)||bounds.extents.y<0.2f||bounds.extents.y>3.f)continue;
        Vec3 head=bounds.center,feet=bounds.center;head.y+=bounds.extents.y;feet.y-=bounds.extents.y;
        Vec3 sh{},sf{};void* ah[]={&head};void* af[]={&feet};
        if(!value(objectCall(cam,"WorldToScreenPoint",{"UnityEngine.Vector3"},ah),sh)||!value(objectCall(cam,"WorldToScreenPoint",{"UnityEngine.Vector3"},af),sf))continue;
        if(sh.z<=0.05f||sf.z<=0.05f)continue;
        float h=(sh.y-sf.y)*height/ph;
        float w=h*0.46f;float x=sh.x*width/pw-w/2;float y=height-sh.y*height/ph;
        if(!std::isfinite(x)||!std::isfinite(y)||!std::isfinite(h)||h<3||h>height*2||x+w<0||x>width||y+h<0||y>height)continue;
        float distance=-1;
        if(cameraPositionValid){Vec3 d{bounds.center.x-cameraPosition.x,bounds.center.y-cameraPosition.y,bounds.center.z-cameraPosition.z};distance=std::sqrt(d.x*d.x+d.y*d.y+d.z*d.z);if(distance<1)continue;}
        result.push_back({x,y,w,h,distance});
        if(refreshTint)applyTint(binding);
    }
    gchandle_free(root);
    status=result.empty()?"No PlayerBindings candidates in view":"Candidate overlay; team / health not mapped";
}
void Runtime::setTint(bool enabled){tint=enabled;if(!tint)restore();lastTint=0;}
void Runtime::setVisualsAllowed(bool allowed){
    if(allowed==visualsAllowed)return;
    if(!allowed)restore();
    visualsAllowed=allowed;lastTint=0;
}
void Runtime::restore(){
    for(auto& s:saved){void* r=gchandle_get_target(s.renderer);void* a=gchandle_get_target(s.materials);
        if(alive(r)&&a){void* args[]={a};objectCall(r,"set_sharedMaterials",{"UnityEngine.Material[]"},args);}
        for(auto h:s.clones){void* obj=gchandle_get_target(h);if(alive(obj)){void* args[]={obj};call(unityObject,"Destroy",nullptr,{"UnityEngine.Object"},args);}gchandle_free(h);}
        gchandle_free(s.renderer);gchandle_free(s.materials);
    }saved.clear();
}
void Runtime::applyTint(void* binding){
    if(!visualsAllowed)return;
    void* rt=type_get_object(class_get_type(rendererClass));void* args[]={rt};
    void* renderers=objectCall(binding,"GetComponentsInChildren",{"System.Type"},args);
    if(!renderers)return;
    Handle root=gchandle_new(renderers,false);
    for(size_t i=0;i<std::min<size_t>(length(renderers),32);i++){
        void* r=element(renderers,i);if(!alive(r))continue;
        void* originals=objectCall(r,"get_sharedMaterials");size_t n=length(originals);if(!n||n>32)continue;
        Saved s{gchandle_new(r,false),gchandle_new(originals,false),{}};
        void* copies=array_new(materialClass,n);Handle copiesRoot=gchandle_new(copies,false);
        bool ok=true;
        for(size_t j=0;j<n;j++){
            void* original=element(originals,j);if(!alive(original)){ok=false;break;}
            void* copy=object_new(materialClass);Handle cr=gchandle_new(copy,false);s.clones.push_back(cr);
            auto ctor=method(materialClass,".ctor",{"UnityEngine.Material"});void* a[]={original};void* ex=nullptr;
            if(!ctor){ok=false;break;}runtime_invoke(ctor,copy,a,&ex);if(ex){ok=false;break;}
            // Reversible visible material tint, not an unverified through-wall shader.
            void* property=string_new("_Color");void* hp[]={property};bool has=false;
            if(!value(objectCall(copy,"HasProperty",{"System.String"},hp),has)||!has){ok=false;break;}
            struct {float r,g,b,a;} color{0.25f,0.95f,0.85f,1.f};void* ca[]={property,&color};
            objectCall(copy,"SetColor",{"System.String","UnityEngine.Color"},ca);
            auto slot=reinterpret_cast<void**>(static_cast<char*>(copies)+array_object_header_size())+j;
            gc_wbarrier_set_field(copies,slot,copy);
        }
        if(ok){void* ca[]={copies};objectCall(r,"set_sharedMaterials",{"UnityEngine.Material[]"},ca);saved.push_back(s);}
        else {saved.push_back(s); /* restore path releases partially created materials as well */}
        gchandle_free(copiesRoot);
    }gchandle_free(root);
}

static NSString* text(const char* s){return s?[NSString stringWithUTF8String:s]:@"";}
static NSString* className(void* c){return [NSString stringWithFormat:@"%@.%@",text(class_get_namespace(c)),text(class_get_name(c))];}
static std::string json(id object){
    NSData* data=[NSJSONSerialization dataWithJSONObject:object options:NSJSONWritingPrettyPrinted error:nil];
    return data?std::string(static_cast<const char*>(data.bytes),data.length):"{}";
}
int Runtime::diagnosticID(void* obj){
    if(!obj)return 0;
    for(size_t i=0;i<diagnosticHandles.size();i++)if(gchandle_get_target(diagnosticHandles[i])==obj)return (int)i+1;
    if(diagnosticHandles.size()>=10000)return 0;
    diagnosticHandles.push_back(gchandle_new(obj,false));return (int)diagnosticHandles.size();
}
std::string Runtime::diagnosticRoots(){
    if(!attach())return json(@{@"error":text(status.c_str())});
    for(auto h:diagnosticHandles)gchandle_free(h);diagnosticHandles.clear();
    NSMutableArray* nodes=[NSMutableArray array];
    void* resources=find("UnityEngine","Resources");
    const char* names[][2]={{"VContainer.Unity","LifetimeScope"},{"Axlebolt.Standoff.Gameplay.Player","PlayerBindings"},{"Axlebolt.Standoff.Content.Definitions.Skin","SkinDefinition"}};
    for(auto& name:names){
        void* klass=find(name[0],name[1]);if(!klass)continue;
        void* rt=type_get_object(class_get_type(klass));void* args[]={rt};
        void* array=call(resources,"FindObjectsOfTypeAll",nullptr,{"System.Type"},args);if(!array)continue;
        Handle root=gchandle_new(array,false);
        for(size_t i=0;i<std::min<size_t>(length(array),2048);i++){
            void* obj=element(array,i);if(!alive(obj))continue;
            [nodes addObject:@{@"id":@(diagnosticID(obj)),@"class":className(object_get_class(obj))}];
        }gchandle_free(root);
    }
    return json(@{@"roots":nodes,@"note":@"Read-only object graph; managed strings are omitted"});
}
std::string Runtime::diagnosticNode(int id){
    if(id<1||(size_t)id>diagnosticHandles.size())return "{\"error\":\"Invalid node ID\"}";
    void* obj=gchandle_get_target(diagnosticHandles[id-1]);if(!obj)return "{\"error\":\"Object collected\"}";
    void* klass=object_get_class(obj);
    if(className(klass)==nil)return "{}";
    NSString* primitive=className(klass);
    if([primitive isEqualToString:@"System.Int32"]){int32_t n=0;value(obj,n);return json(@{@"id":@(id),@"class":primitive,@"value":@(n)});}
    if([primitive isEqualToString:@"System.Boolean"]){bool n=false;value(obj,n);return json(@{@"id":@(id),@"class":primitive,@"value":@(n)});}
    if([primitive isEqualToString:@"System.UInt16"]){uint16_t n=0;value(obj,n);return json(@{@"id":@(id),@"class":primitive,@"value":@(n)});}
    if([primitive isEqualToString:@"System.Byte"]){uint8_t n=0;value(obj,n);return json(@{@"id":@(id),@"class":primitive,@"value":@(n)});}
    NSMutableArray* fields=[NSMutableArray array];
    for(void* c=klass;c;c=class_get_parent(c)){
        void* iterator=nullptr;
        while(void* field=class_get_fields(c,&iterator)){
            if(field_get_flags(field)&0x10)continue; // no static state or service construction
            char* tn=type_get_name(field_get_type(field));NSString* type=text(tn);if(tn)ilfree(tn);
            // Never export account strings, credentials, user names or network data.
            NSString* name=text(field_get_name(field));
            if([type isEqualToString:@"System.String"]||[type isEqualToString:@"System.Byte[]"])continue;
            void* child=field_get_value_object(field,obj);
            [fields addObject:@{@"name":name,@"type":type,@"ref":@(diagnosticID(child))}];
        }
    }
    NSMutableArray* elements=[NSMutableArray array];
    if(class_get_rank(klass)==1){
        size_t count=std::min<size_t>(length(obj),256);
        for(size_t i=0;i<count;i++){
            int32_t index=(int32_t)i;void* args[]={&index};
            void* item=objectCall(obj,"GetValue",{"System.Int32"},args);
            if(item)[elements addObject:@{@"index":@(i),@"ref":@(diagnosticID(item)),@"class":className(object_get_class(item))}];
        }
    }
    NSMutableDictionary* result=[@{@"id":@(id),@"class":className(klass),@"fields":fields,@"elements":elements} mutableCopy];
    // Primitive values here are structural collection metadata / cosmetic IDs.
    NSString* cn=className(klass);
    if([cn isEqualToString:@"System.Int32"]){int32_t n=0;value(obj,n);result[@"value"]=@(n);}
    if([cn isEqualToString:@"System.Boolean"]){bool n=false;value(obj,n);result[@"value"]=@(n);}
    if([cn isEqualToString:@"System.UInt16"]){uint16_t n=0;value(obj,n);result[@"value"]=@(n);}
    return json(result);
}
}
