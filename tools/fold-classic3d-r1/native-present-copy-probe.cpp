// Separate app-only GPU publication diagnostic. Hardware D3D11 only; original15cube render workload.
// --private-copy0 is the direct swapchain RTV control;1 uses private RTV then one GPUCopyResource perPresent.
// Existing hostCopyTinySync can add aCPUcompletion roundtrip. This is not a driverfix orperformanceacceptance.
// Build: cl /std:c++17 /EHsc /O2 /MT /Zi native-gpu-bench.cpp /link d3d11.lib dxgi.lib d3dcompiler.lib user32.lib gdi32.lib
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#define UNICODE
#define _UNICODE
#include <windows.h>
#include <d3d11.h>
#include <dxgi1_2.h>
#include <d3dcompiler.h>
#include <wrl/client.h>
#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>
using Microsoft::WRL::ComPtr;

static std::string utf8(const std::wstring& s) {
    if(s.empty())return {};
    int n=WideCharToMultiByte(CP_UTF8,0,s.data(),(int)s.size(),nullptr,0,nullptr,nullptr);
    std::string out(n,'\0');WideCharToMultiByte(CP_UTF8,0,s.data(),(int)s.size(),out.data(),n,nullptr,nullptr);return out;
}
static std::string quote(const std::string& s) {
    std::ostringstream o;o<<'"';
    for(unsigned char c:s){switch(c){case '"':o<<"\\\"";break;case '\\':o<<"\\\\";break;case '\n':o<<"\\n";break;case '\r':o<<"\\r";break;case '\t':o<<"\\t";break;default:if(c<32)o<<"\\u"<<std::hex<<std::setw(4)<<std::setfill('0')<<(unsigned)c<<std::dec;else o<<(char)c;}}
    o<<'"';return o.str();
}
static std::string utcNow(){SYSTEMTIME t;GetSystemTime(&t);char b[80];sprintf_s(b,"%04u-%02u-%02uT%02u:%02u:%02u.%03uZ",t.wYear,t.wMonth,t.wDay,t.wHour,t.wMinute,t.wSecond,t.wMilliseconds);return b;}
static std::string hexhr(HRESULT h){char b[20];sprintf_s(b,"0x%08lX",(unsigned long)h);return b;}
static double qpc(){static LARGE_INTEGER f=[](){LARGE_INTEGER x;QueryPerformanceFrequency(&x);return x;}();LARGE_INTEGER t;QueryPerformanceCounter(&t);return(double)t.QuadPart/(double)f.QuadPart;}
static void check(HRESULT hr,const char* stage){if(FAILED(hr))throw std::runtime_error(std::string(stage)+" "+hexhr(hr));}
static double percentile(std::vector<double> values,double p){if(values.empty())return 0;std::sort(values.begin(),values.end());return values[(size_t)std::floor(p*(values.size()-1))];}
struct Config {double warmup=5,duration=30;UINT width=960,height=640,vsync=1;UINT privateCopy=0;std::wstring output=L"native-present-copy-probe.json";};
struct Evidence {
    std::string start=utcNow(),finish,status="initializing",stage="arguments",adapter,driverVersion;
    UINT vendor=0,device=0,subsystem=0,revision=0,featureLevel=0;SIZE_T dedicatedMemory=0,sharedMemory=0;
    std::vector<std::string> errors;std::vector<double> frameMs,presentMs;uint64_t frames=0,drawCalls=0,occluded=0,minimized=0;
    double measuredSeconds=0;HRESULT removedReason=S_OK;UINT backWidth=0,backHeight=0;bool exitedEarly=false;
    bool foregroundVerifiedAtStart=false,foregroundAttachmentAttempted=false,foregroundAttachmentSucceeded=false;
    DWORD foregroundPidAtStart=0;uint64_t foregroundLostChecks=0,foregroundLossTransitions=0,measurementForegroundLostChecks=0;double foregroundLostSeconds=0,measurementForegroundLostSeconds=0;
    std::vector<std::string> foregroundEvents;
    uint64_t renderedFramesTotal=0,copyCallsTotal=0,copyCallsMeasured=0,targetRecreations=0;
    std::vector<double> copyMs;
    std::string privateSourceIdentity,firstCopyDestinationIdentity,lastCopyDestinationIdentity;
    uint64_t copyDestinationApiChanges=0;
    bool privateRtvIdentityVerified=false;
    D3D11_TEXTURE2D_DESC privateDesc{},copyDestinationDesc{};

};
static void writeEvidence(const Config& c,const Evidence& e){
    std::filesystem::path p(c.output);if(p.has_parent_path())std::filesystem::create_directories(p.parent_path());
    auto tmp=p;tmp+=L".tmp";std::ofstream o(tmp,std::ios::binary|std::ios::trunc);if(!o)throw std::runtime_error("Cannot open evidence output");
    o<<std::setprecision(12)<<"{\n\"schemaVersion\":1,\n\"startedAt\":"<<quote(e.start)<<",\n\"finishedAt\":"<<quote(e.finish)<<",\n\"status\":"<<quote(e.status)<<",\n\"lastStage\":"<<quote(e.stage)<<",\n"
      <<"\"api\":\"Direct3D 11\",\n\"requestedDeviceType\":\"D3D_DRIVER_TYPE_HARDWARE\",\n\"warpFallbackAllowed\":false,\n"
      <<"\"adapter\":{\"description\":"<<quote(e.adapter)<<",\"vendorId\":"<<e.vendor<<",\"deviceId\":"<<e.device<<",\"subsystemId\":"<<e.subsystem<<",\"revision\":"<<e.revision<<",\"dedicatedVideoMemoryBytes\":"<<e.dedicatedMemory<<",\"sharedSystemMemoryBytes\":"<<e.sharedMemory<<",\"umdVersionFromDXGI\":"<<quote(e.driverVersion)<<"},\n"
      <<"\"featureLevel\":"<<e.featureLevel<<",\n\"config\":{\"warmupSeconds\":"<<c.warmup<<",\"durationSeconds\":"<<c.duration<<",\"width\":"<<c.width<<",\"height\":"<<c.height<<",\"syncInterval\":"<<c.vsync<<",\"privateCopy\":"<<c.privateCopy<<",\"windowX\":26,\"windowY\":26},\n"
      <<"\"workload\":{\"cubes\":15,\"drawCallsPerFrame\":15,\"trianglesPerFrame\":180,\"depthTest\":true,\"swapEffect\":\"FLIP_DISCARD\"},\n"
      <<"\"measured\":{\"seconds\":"<<e.measuredSeconds<<",\"successfulPresents\":"<<e.frames<<",\"drawCalls\":"<<e.drawCalls<<",\"framesPerSecond\":"<<(e.measuredSeconds>0?e.frames/e.measuredSeconds:0)<<",\"occludedPresents\":"<<e.occluded<<",\"minimizedIterations\":"<<e.minimized<<",\"exitedEarly\":"<<(e.exitedEarly?"true":"false")<<",\"backBufferWidth\":"<<e.backWidth<<",\"backBufferHeight\":"<<e.backHeight<<"},\n"
      <<"\"frameIntervalMs\":{\"samples\":"<<e.frameMs.size()<<",\"p50\":"<<percentile(e.frameMs,.5)<<",\"p95\":"<<percentile(e.frameMs,.95)<<",\"p99\":"<<percentile(e.frameMs,.99)<<",\"max\":"<<percentile(e.frameMs,1)<<",\"over16_7\":"<<std::count_if(e.frameMs.begin(),e.frameMs.end(),[](double x){return x>16.7;})<<",\"over25\":"<<std::count_if(e.frameMs.begin(),e.frameMs.end(),[](double x){return x>25;})<<"},\n"
      <<"\"presentCallMs\":{\"samples\":"<<e.presentMs.size()<<",\"p50\":"<<percentile(e.presentMs,.5)<<",\"p95\":"<<percentile(e.presentMs,.95)<<",\"max\":"<<percentile(e.presentMs,1)<<"},\n"
      <<"\"copyProbe\":{\"renderedFramesTotal\":"<<e.renderedFramesTotal<<",\"copyCallsTotal\":"<<e.copyCallsTotal<<",\"copyCallsMeasured\":"<<e.copyCallsMeasured<<",\"targetRecreations\":"<<e.targetRecreations<<",\"privateRtvIdentityVerified\":"<<(e.privateRtvIdentityVerified?"true":"false")<<",\"privateSourceApiIdentity\":"<<quote(e.privateSourceIdentity)<<",\"firstDestinationApiIdentity\":"<<quote(e.firstCopyDestinationIdentity)<<",\"lastDestinationApiIdentity\":"<<quote(e.lastCopyDestinationIdentity)<<",\"destinationApiChanges\":"<<e.copyDestinationApiChanges<<",\"privateDescriptor\":{\"width\":"<<e.privateDesc.Width<<",\"height\":"<<e.privateDesc.Height<<",\"format\":"<<e.privateDesc.Format<<",\"sampleCount\":"<<e.privateDesc.SampleDesc.Count<<",\"bindFlags\":"<<e.privateDesc.BindFlags<<",\"miscFlags\":"<<e.privateDesc.MiscFlags<<"},\"destinationDescriptor\":{\"width\":"<<e.copyDestinationDesc.Width<<",\"height\":"<<e.copyDestinationDesc.Height<<",\"format\":"<<e.copyDestinationDesc.Format<<",\"sampleCount\":"<<e.copyDestinationDesc.SampleDesc.Count<<"}},\n"
      <<"\"copyCallMs\":{\"samples\":"<<e.copyMs.size()<<",\"p50\":"<<percentile(e.copyMs,.5)<<",\"p95\":"<<percentile(e.copyMs,.95)<<",\"max\":"<<percentile(e.copyMs,1)<<",\"interpretation\":\"CPU duration of CopyResource API call only; not isolated GPU copy time. Existing host TinySync can block this call. Full frame interval includes all copy, driver and pacing cost.\"},\n"
      <<"\"deviceRemovedReason\":"<<quote(hexhr(e.removedReason))<<",\n\"errors\":[";
    for(size_t i=0;i<e.errors.size();i++){if(i)o<<',';o<<quote(e.errors[i]);}
    o<<"],\n\"foreground\":{\"foregroundVerifiedAtStart\":"<<(e.foregroundVerifiedAtStart?"true":"false")<<",\"foregroundPidAtStart\":"<<e.foregroundPidAtStart<<",\"benchmarkPid\":"<<GetCurrentProcessId()<<",\"attachmentAttempted\":"<<(e.foregroundAttachmentAttempted?"true":"false")<<",\"attachmentSucceeded\":"<<(e.foregroundAttachmentSucceeded?"true":"false")<<",\"lostChecks\":"<<e.foregroundLostChecks<<",\"lossTransitions\":"<<e.foregroundLossTransitions<<",\"lostSecondsApprox\":"<<e.foregroundLostSeconds<<",\"measurementLostChecks\":"<<e.measurementForegroundLostChecks<<",\"measurementLostSecondsApprox\":"<<e.measurementForegroundLostSeconds<<",\"events\":[";
    for(size_t i=0;i<e.foregroundEvents.size();i++){if(i)o<<',';o<<e.foregroundEvents[i];}
    o<<"]},\n\"frameIntervalSamplesMs\":[";for(size_t i=0;i<e.frameMs.size();i++){if(i)o<<',';o<<e.frameMs[i];}
    o<<"],\n\"copyCallSamplesMs\":[";for(size_t i=0;i<e.copyMs.size();i++){if(i)o<<',';o<<e.copyMs[i];}
    o<<"],\n\"presentCallSamplesMs\":[";for(size_t i=0;i<e.presentMs.size();i++){if(i)o<<',';o<<e.presentMs[i];}
    o<<"],\n\"interpretation\":\"QPC intervals between completed successful Present calls include application CPU work, runtime/driver submission and vsync waits. They do not prove physical scanout cadence, independent GPU execution time or absence of dropped compositor frames. Correlate with guest vblank and Android SurfaceFlinger.\"\n}\n";
    o.close();if(!o)throw std::runtime_error("Evidence output write failed");
    // Retry only transient sharing/access failures. Keep the complete .tmp on
    // fatal failure; never skip evidence checkpoints or hide rendering errors.
    const ULONGLONG replaceStarted=GetTickCount64();
    std::vector<DWORD> replaceErrors;
    for(UINT attempt=1;attempt<=11;++attempt){
        if(MoveFileExW(tmp.c_str(),p.c_str(),MOVEFILE_REPLACE_EXISTING|MOVEFILE_WRITE_THROUGH)){
            if(!replaceErrors.empty()){
                std::cerr<<"Evidence replacement recovered operation=MoveFileExW stage="<<e.stage
                         <<" attempts="<<attempt<<" elapsedMs="<<(GetTickCount64()-replaceStarted)<<" win32Errors=";
                for(size_t i=0;i<replaceErrors.size();++i){if(i)std::cerr<<',';std::cerr<<replaceErrors[i];}
                std::cerr<<'\n';
            }
            return;
        }
        const DWORD error=GetLastError(); // Capture immediately after failing API.
        replaceErrors.push_back(error);
        const bool transient=error==ERROR_SHARING_VIOLATION||error==ERROR_LOCK_VIOLATION||
                             error==ERROR_ACCESS_DENIED||error==ERROR_USER_MAPPED_FILE;
        if(!transient||attempt==11||GetTickCount64()-replaceStarted>=200){
            std::ostringstream message;
            message<<"Evidence output replacement failed operation=MoveFileExW stage="<<e.stage
                   <<" win32Error="<<error<<" hresult="<<hexhr(HRESULT_FROM_WIN32(error))
                   <<" attempts="<<attempt<<" elapsedMs="<<(GetTickCount64()-replaceStarted)
                   <<" temporary="<<utf8(tmp.wstring())<<" output="<<utf8(p.wstring())<<" win32Errors=";
            for(size_t i=0;i<replaceErrors.size();++i){if(i)message<<',';message<<replaceErrors[i];}
            if(!e.errors.empty()){message<<" preservedBenchmarkErrors=";for(const auto& prior:e.errors)message<<'['<<prior<<']';}
            throw std::runtime_error(message.str());
        }
        Sleep(20); // At most10retries/200ms requested sleep; OS API time is extra.
    }

}
static LRESULT CALLBACK wndproc(HWND h,UINT m,WPARAM w,LPARAM l){if(m==WM_CLOSE){DestroyWindow(h);return 0;}if(m==WM_DESTROY){PostQuitMessage(0);return 0;}return DefWindowProcW(h,m,w,l);}
static void activateOwnedWindow(HWND window,Evidence& ev){
    DWORD current=GetCurrentThreadId();HWND before=GetForegroundWindow();DWORD owner=before?GetWindowThreadProcessId(before,nullptr):0;
    bool attached=false;
    if(owner&&owner!=current){ev.foregroundAttachmentAttempted=true;attached=AttachThreadInput(current,owner,TRUE)!=FALSE;ev.foregroundAttachmentSucceeded=attached;}
    BringWindowToTop(window);SetForegroundWindow(window);
    if(attached)AttachThreadInput(current,owner,FALSE);
    // Let already queued activation messages settle before starting any timing.
    Sleep(50);MSG msg;while(PeekMessageW(&msg,nullptr,0,0,PM_REMOVE)){TranslateMessage(&msg);DispatchMessageW(&msg);}
    HWND actual=GetForegroundWindow();if(actual)GetWindowThreadProcessId(actual,&ev.foregroundPidAtStart);
    ev.foregroundVerifiedAtStart=(actual==window)&&IsWindowVisible(window)&&!IsIconic(window);
    if(!ev.foregroundVerifiedAtStart)throw std::runtime_error("Owned benchmark window could not become the visible foreground window; refusing to report a hidden run as success");
}
struct Vertex {float p[3],c[3];};struct Constants {float time,phase,offsetX,offsetY,aspect,pad[3];};
static const char* shaderSource=R"(
cbuffer Params:register(b0){float time;float phase;float2 offset;float aspect;float3 padding;};
struct VSIn{float3 position:POSITION;float3 color:COLOR;};struct VSOut{float4 position:SV_POSITION;float3 color:COLOR;};
VSOut vsMain(VSIn v){float a=time*.8+phase,b=time*.6+phase*.7;float3 p=v.position*.58;float3 q=float3(cos(a)*p.x+sin(a)*p.z,p.y,-sin(a)*p.x+cos(a)*p.z);p=float3(q.x,cos(b)*q.y-sin(b)*q.z,sin(b)*q.y+cos(b)*q.z);p.xy+=offset;float z=p.z+7.;VSOut o;o.position=float4(p.x*2.1/aspect,p.y*2.1,(z-1.)*1.05,z);o.color=v.color*(.65+.35*(p.z+.7)/1.4);return o;}
float4 psMain(VSOut v):SV_TARGET{return float4(v.color,1.);}
)";

int wmain(int argc,wchar_t** argv){
    Config cfg;Evidence ev;bool outputOwned=false;HANDLE done=CreateEventW(nullptr,TRUE,FALSE,nullptr);const DWORD doneError=done?ERROR_SUCCESS:GetLastError();std::thread watchdog;HWND window=nullptr;
    ComPtr<ID3D11Device> device;ComPtr<ID3D11DeviceContext> ctx;int result=0;
    try{
        for(int i=1;i<argc;i++){std::wstring a=argv[i];if(i+1>=argc)throw std::runtime_error("Argument value missing");std::wstring v=argv[++i];if(a==L"--warmup")cfg.warmup=std::stod(v);else if(a==L"--duration")cfg.duration=std::stod(v);else if(a==L"--output")cfg.output=v;else if(a==L"--width")cfg.width=std::stoul(v);else if(a==L"--height")cfg.height=std::stoul(v);else if(a==L"--vsync")cfg.vsync=std::stoul(v);else if(a==L"--private-copy") {if(v!=L"0"&&v!=L"1")throw std::runtime_error("private-copy must be 0 or 1");cfg.privateCopy=v==L"1";}else throw std::runtime_error("Unknown argument");}
        if(!std::isfinite(cfg.warmup)||!std::isfinite(cfg.duration)||cfg.warmup<0||cfg.warmup>120||cfg.duration<1||cfg.duration>600||cfg.width<320||cfg.width>3840||cfg.height<240||cfg.height>2160||cfg.vsync>1)throw std::runtime_error("Argument out of range");
        // Claim only freshowned report/scratch paths before anygraphics action.
        const std::filesystem::path owned(cfg.output);
        if(owned.has_parent_path())std::filesystem::create_directories(owned.parent_path());
        for(const auto& suffix:{L".tmp",L".timeout.json"}){
            const auto scratch=std::filesystem::path(cfg.output+suffix);
            const DWORD attr=GetFileAttributesW(scratch.c_str());
            if(attr!=INVALID_FILE_ATTRIBUTES)throw std::runtime_error("Output scratch already exists; refusing overwrite");
            const DWORD error=GetLastError();
            if(error!=ERROR_FILE_NOT_FOUND&&error!=ERROR_PATH_NOT_FOUND)throw std::runtime_error("Output scratch check "+hexhr(HRESULT_FROM_WIN32(error)));
        }
        HANDLE claim=CreateFileW(owned.c_str(),GENERIC_WRITE,FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_SHARE_DELETE,nullptr,CREATE_NEW,FILE_ATTRIBUTE_NORMAL,nullptr);
        if(claim==INVALID_HANDLE_VALUE)throw std::runtime_error("Output must be a new owned path "+hexhr(HRESULT_FROM_WIN32(GetLastError())));
        outputOwned=true;
        if(!CloseHandle(claim))throw std::runtime_error("Close output claim "+hexhr(HRESULT_FROM_WIN32(GetLastError())));
        if(!done)throw std::runtime_error("Create watchdog event "+hexhr(HRESULT_FROM_WIN32(doneError)));
        writeEvidence(cfg,ev);
        // A blocked driver call cannot be cancelled cleanly. Preserve the last checkpoint and
        // emit an explicit timeout sidecar before terminating this benchmark process only.
        watchdog=std::thread([&cfg,done](){DWORD ms=(DWORD)((cfg.warmup+cfg.duration+30)*1000);if(WaitForSingleObject(done,ms)==WAIT_TIMEOUT){std::ofstream o(std::filesystem::path(cfg.output+L".timeout.json"));o<<"{\"status\":\"watchdog_timeout\",\"interpretation\":\"Benchmark exceeded configured duration plus30seconds; last main JSON is partial. Only the owned benchmark process is terminated.\"}\n";o.close();TerminateProcess(GetCurrentProcess(),124);}});
        ev.stage="D3D11CreateDevice";writeEvidence(cfg,ev);
        D3D_FEATURE_LEVEL fl;D3D_FEATURE_LEVEL levels[]={D3D_FEATURE_LEVEL_11_1,D3D_FEATURE_LEVEL_11_0};
        HRESULT hr=D3D11CreateDevice(nullptr,D3D_DRIVER_TYPE_HARDWARE,nullptr,D3D11_CREATE_DEVICE_BGRA_SUPPORT,levels,2,D3D11_SDK_VERSION,&device,&fl,&ctx);
        if(hr==E_INVALIDARG)hr=D3D11CreateDevice(nullptr,D3D_DRIVER_TYPE_HARDWARE,nullptr,D3D11_CREATE_DEVICE_BGRA_SUPPORT,levels+1,1,D3D11_SDK_VERSION,&device,&fl,&ctx);
        check(hr,"D3D11CreateDevice(HARDWARE)");ev.featureLevel=(UINT)fl;
        ComPtr<IDXGIDevice> dxgi;check(device.As(&dxgi),"Query IDXGIDevice");ComPtr<IDXGIAdapter> adapter;check(dxgi->GetAdapter(&adapter),"GetAdapter");DXGI_ADAPTER_DESC ad;check(adapter->GetDesc(&ad),"GetDesc");ev.adapter=utf8(ad.Description);ev.vendor=ad.VendorId;ev.device=ad.DeviceId;ev.subsystem=ad.SubSysId;ev.revision=ad.Revision;ev.dedicatedMemory=ad.DedicatedVideoMemory;ev.sharedMemory=ad.SharedSystemMemory;
        if(ad.VendorId==0x1414&&ad.DeviceId==0x008c)throw std::runtime_error("Microsoft software adapter rejected despite hardware request");
        LARGE_INTEGER version={};if(SUCCEEDED(adapter->CheckInterfaceSupport(__uuidof(ID3D11Device),&version))){std::ostringstream v;v<<HIWORD(version.HighPart)<<'.'<<LOWORD(version.HighPart)<<'.'<<HIWORD(version.LowPart)<<'.'<<LOWORD(version.LowPart);ev.driverVersion=v.str();}
        ev.stage="window-and-swapchain";writeEvidence(cfg,ev);
        WNDCLASSW wc={};wc.lpfnWndProc=wndproc;wc.hInstance=GetModuleHandleW(nullptr);wc.lpszClassName=L"CodexNativePresentCopyProbe";wc.hCursor=LoadCursorW(nullptr,IDC_ARROW);if(!RegisterClassW(&wc)&&GetLastError()!=ERROR_CLASS_ALREADY_EXISTS)throw std::runtime_error("RegisterClass failed");
        RECT wr={0,0,(LONG)cfg.width,(LONG)cfg.height};AdjustWindowRect(&wr,WS_OVERLAPPEDWINDOW,FALSE);
        window=CreateWindowW(wc.lpszClassName,L"Native D3D11 copy probe - 15 rotating cubes",WS_OVERLAPPEDWINDOW,26,26,wr.right-wr.left,wr.bottom-wr.top,nullptr,nullptr,wc.hInstance,nullptr);if(!window)throw std::runtime_error("CreateWindow failed");
        ComPtr<IDXGIFactory2> factory;check(adapter->GetParent(IID_PPV_ARGS(&factory)),"GetParent factory2");
        DXGI_SWAP_CHAIN_DESC1 sd={};sd.Width=cfg.width;sd.Height=cfg.height;sd.Format=DXGI_FORMAT_R8G8B8A8_UNORM;sd.SampleDesc.Count=1;sd.BufferUsage=DXGI_USAGE_RENDER_TARGET_OUTPUT;sd.BufferCount=2;sd.SwapEffect=DXGI_SWAP_EFFECT_FLIP_DISCARD;sd.Scaling=DXGI_SCALING_STRETCH;sd.AlphaMode=DXGI_ALPHA_MODE_IGNORE;
        ComPtr<IDXGISwapChain1> swap;check(factory->CreateSwapChainForHwnd(device.Get(),window,&sd,nullptr,nullptr,&swap),"CreateSwapChainForHwnd");factory->MakeWindowAssociation(window,DXGI_MWA_NO_ALT_ENTER);
        ComPtr<ID3D11RenderTargetView> rtv;ComPtr<ID3D11DepthStencilView> dsv;
        ComPtr<ID3D11Texture2D> privateColor;ComPtr<ID3D11Resource> actualPrivateRtvResource;
        auto targets=[&](UINT width,UINT height){ComPtr<ID3D11Texture2D> back;check(swap->GetBuffer(0,IID_PPV_ARGS(&back)),"GetBuffer");if(cfg.privateCopy){
            D3D11_TEXTURE2D_DESC source={};back->GetDesc(&source);
            source.Usage=D3D11_USAGE_DEFAULT;source.BindFlags=D3D11_BIND_RENDER_TARGET;source.CPUAccessFlags=0;source.MiscFlags=0;
            if(source.MipLevels!=1||source.ArraySize!=1||source.SampleDesc.Count!=1||source.Format!=DXGI_FORMAT_R8G8B8A8_UNORM)throw std::runtime_error("Unsupported private copy target shape");
            check(device->CreateTexture2D(&source,nullptr,&privateColor),"CreatePrivateColor");
            check(device->CreateRenderTargetView(privateColor.Get(),nullptr,&rtv),"CreatePrivateRTV");
            rtv->GetResource(&actualPrivateRtvResource);
            if(!actualPrivateRtvResource)throw std::runtime_error("Private RTV GetResource returned NULL");
            ComPtr<IUnknown> boundIdentity,createdIdentity;check(actualPrivateRtvResource.As(&boundIdentity),"PrivateRTVresourceidentity");check(privateColor.As(&createdIdentity),"PrivateColoridentity");
            if(boundIdentity.Get()!=createdIdentity.Get())throw std::runtime_error("Private RTV does not reference created private color");
            ev.privateRtvIdentityVerified=true;ev.privateDesc=source;std::ostringstream identity;identity<<boundIdentity.Get();ev.privateSourceIdentity=identity.str();
        }else{check(device->CreateRenderTargetView(back.Get(),nullptr,&rtv),"CreateRenderTargetView");}
        ev.targetRecreations++;D3D11_TEXTURE2D_DESC dd={};dd.Width=width;dd.Height=height;dd.MipLevels=dd.ArraySize=1;dd.Format=DXGI_FORMAT_D24_UNORM_S8_UINT;dd.SampleDesc.Count=1;dd.Usage=D3D11_USAGE_DEFAULT;dd.BindFlags=D3D11_BIND_DEPTH_STENCIL;ComPtr<ID3D11Texture2D> depth;check(device->CreateTexture2D(&dd,nullptr,&depth),"CreateDepthTexture");check(device->CreateDepthStencilView(depth.Get(),nullptr,&dsv),"CreateDepthView");ev.backWidth=width;ev.backHeight=height;};targets(cfg.width,cfg.height);
        ev.stage="compile-shaders";writeEvidence(cfg,ev);
        ComPtr<ID3DBlob> vsBlob,psBlob,messages;hr=D3DCompile(shaderSource,strlen(shaderSource),"native-gpu-bench.hlsl",nullptr,nullptr,"vsMain","vs_5_0",D3DCOMPILE_OPTIMIZATION_LEVEL3,0,&vsBlob,&messages);if(FAILED(hr)&&messages)ev.errors.push_back(std::string((char*)messages->GetBufferPointer(),messages->GetBufferSize()));check(hr,"CompileVS");messages.Reset();
        hr=D3DCompile(shaderSource,strlen(shaderSource),"native-gpu-bench.hlsl",nullptr,nullptr,"psMain","ps_5_0",D3DCOMPILE_OPTIMIZATION_LEVEL3,0,&psBlob,&messages);if(FAILED(hr)&&messages)ev.errors.push_back(std::string((char*)messages->GetBufferPointer(),messages->GetBufferSize()));check(hr,"CompilePS");
        ComPtr<ID3D11VertexShader> vs;ComPtr<ID3D11PixelShader> ps;check(device->CreateVertexShader(vsBlob->GetBufferPointer(),vsBlob->GetBufferSize(),nullptr,&vs),"CreateVS");check(device->CreatePixelShader(psBlob->GetBufferPointer(),psBlob->GetBufferSize(),nullptr,&ps),"CreatePS");
        D3D11_INPUT_ELEMENT_DESC ie[]={{"POSITION",0,DXGI_FORMAT_R32G32B32_FLOAT,0,0,D3D11_INPUT_PER_VERTEX_DATA,0},{"COLOR",0,DXGI_FORMAT_R32G32B32_FLOAT,0,12,D3D11_INPUT_PER_VERTEX_DATA,0}};ComPtr<ID3D11InputLayout> layout;check(device->CreateInputLayout(ie,2,vsBlob->GetBufferPointer(),vsBlob->GetBufferSize(),&layout),"CreateInputLayout");
        const float corners[6][4][3]={{{1,-1,-1},{1,1,-1},{1,1,1},{1,-1,1}},{{-1,-1,1},{-1,1,1},{-1,1,-1},{-1,-1,-1}},{{-1,1,-1},{-1,1,1},{1,1,1},{1,1,-1}},{{-1,-1,1},{-1,-1,-1},{1,-1,-1},{1,-1,1}},{{1,-1,1},{1,1,1},{-1,1,1},{-1,-1,1}},{{-1,-1,-1},{-1,1,-1},{1,1,-1},{1,-1,-1}}};
        const float colors[6][3]={{1,.25f,.2f},{.2f,.7f,1},{.25f,1,.6f},{1,.8f,.2f},{.8f,.3f,1},{.25f,1,1}};Vertex vertices[36];int n=0;for(int f=0;f<6;f++)for(int i:{0,1,2,0,2,3}){memcpy(vertices[n].p,corners[f][i],12);memcpy(vertices[n++].c,colors[f],12);}
        D3D11_BUFFER_DESC bd={};bd.ByteWidth=sizeof(vertices);bd.Usage=D3D11_USAGE_IMMUTABLE;bd.BindFlags=D3D11_BIND_VERTEX_BUFFER;D3D11_SUBRESOURCE_DATA init={vertices,0,0};ComPtr<ID3D11Buffer> vb;check(device->CreateBuffer(&bd,&init,&vb),"CreateVB");bd={};bd.ByteWidth=sizeof(Constants);bd.Usage=D3D11_USAGE_DEFAULT;bd.BindFlags=D3D11_BIND_CONSTANT_BUFFER;ComPtr<ID3D11Buffer> cb;check(device->CreateBuffer(&bd,nullptr,&cb),"CreateCB");
        D3D11_RASTERIZER_DESC rsd={};rsd.FillMode=D3D11_FILL_SOLID;rsd.CullMode=D3D11_CULL_NONE;rsd.DepthClipEnable=TRUE;ComPtr<ID3D11RasterizerState> raster;check(device->CreateRasterizerState(&rsd,&raster),"CreateRasterizerState");
        ShowWindow(window,SW_SHOWNORMAL);UpdateWindow(window);ev.stage="verify-foreground";activateOwnedWindow(window,ev);ev.status="running";ev.stage="warmup";writeEvidence(cfg,ev);
        const double start=qpc(),measureStart=start+cfg.warmup,end=measureStart+cfg.duration;double previous=0,lastCheckpoint=start,previousFocusCheck=start;bool quit=false,previouslyForeground=true;
        while(qpc()<end){MSG msg;while(PeekMessageW(&msg,nullptr,0,0,PM_REMOVE)){if(msg.message==WM_QUIT)quit=true;TranslateMessage(&msg);DispatchMessageW(&msg);}if(quit){ev.exitedEarly=true;break;}double now=qpc();
            HWND foreground=GetForegroundWindow();bool isForeground=(foreground==window);DWORD foregroundPid=0;if(foreground)GetWindowThreadProcessId(foreground,&foregroundPid);
            if(!previouslyForeground){ev.foregroundLostSeconds+=now-previousFocusCheck;ev.measurementForegroundLostSeconds+=std::max(0.0,std::min(now,end)-std::max(previousFocusCheck,measureStart));}
            if(!isForeground){ev.foregroundLostChecks++;if(now>=measureStart)ev.measurementForegroundLostChecks++;}
            if(isForeground!=previouslyForeground){if(!isForeground)ev.foregroundLossTransitions++;std::ostringstream event;event<<std::setprecision(12)<<"{\"elapsedSeconds\":"<<(now-start)<<",\"phase\":"<<quote(now<measureStart?"warmup":"measurement")<<",\"foreground\":"<<(isForeground?"true":"false")<<",\"foregroundPid\":"<<foregroundPid<<"}";ev.foregroundEvents.push_back(event.str());}
            previouslyForeground=isForeground;previousFocusCheck=now;
            if(IsIconic(window)){ev.minimized++;Sleep(10);continue;}
            RECT cr;GetClientRect(window,&cr);UINT width=(UINT)std::max<LONG>(1,cr.right),height=(UINT)std::max<LONG>(1,cr.bottom);
            if(width!=ev.backWidth||height!=ev.backHeight){ctx->OMSetRenderTargets(0,nullptr,nullptr);rtv.Reset();dsv.Reset();actualPrivateRtvResource.Reset();privateColor.Reset();check(swap->ResizeBuffers(0,width,height,DXGI_FORMAT_UNKNOWN,0),"ResizeBuffers");targets(width,height);}
            const float bg[]={.035f,.065f,.12f,1};ctx->ClearRenderTargetView(rtv.Get(),bg);ctx->ClearDepthStencilView(dsv.Get(),D3D11_CLEAR_DEPTH|D3D11_CLEAR_STENCIL,1,0);ID3D11RenderTargetView* rt=rtv.Get();ctx->OMSetRenderTargets(1,&rt,dsv.Get());D3D11_VIEWPORT vp={0,0,(FLOAT)width,(FLOAT)height,0,1};ctx->RSSetViewports(1,&vp);ctx->RSSetState(raster.Get());ctx->IASetInputLayout(layout.Get());UINT stride=sizeof(Vertex),offset=0;ID3D11Buffer* vertexBuffer=vb.Get();ctx->IASetVertexBuffers(0,1,&vertexBuffer,&stride,&offset);ctx->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);ctx->VSSetShader(vs.Get(),nullptr,0);ctx->PSSetShader(ps.Get(),nullptr,0);ID3D11Buffer* constantBuffer=cb.Get();ctx->VSSetConstantBuffers(0,1,&constantBuffer);
            for(int y=0;y<3;y++)for(int x=0;x<5;x++){Constants c={(float)(now-start),(y*5+x)*.37f,(x-2)*1.7f,(y-1)*1.7f,(float)width/height,{0,0,0}};ctx->UpdateSubresource(cb.Get(),0,nullptr,&c,0,0);ctx->Draw(36,0);}
            ev.renderedFramesTotal++;
            double frameCopyMs=0;
            if(cfg.privateCopy){
                ComPtr<ID3D11Texture2D> currentBack;check(swap->GetBuffer(0,IID_PPV_ARGS(&currentBack)),"GetCurrentCopyDestination");
                if(!currentBack)throw std::runtime_error("GetBuffer returned NULL");
                D3D11_TEXTURE2D_DESC desc={};currentBack->GetDesc(&desc);
                if(desc.Width!=ev.privateDesc.Width||desc.Height!=ev.privateDesc.Height||desc.Format!=ev.privateDesc.Format||desc.MipLevels!=ev.privateDesc.MipLevels||desc.ArraySize!=ev.privateDesc.ArraySize||desc.SampleDesc.Count!=ev.privateDesc.SampleDesc.Count||desc.SampleDesc.Quality!=ev.privateDesc.SampleDesc.Quality)throw std::runtime_error("Copy destination descriptor changed");
                if(!actualPrivateRtvResource)throw std::runtime_error("Missing actual private RTV resource");
                std::ostringstream id;id<<currentBack.Get();const std::string current=id.str();
                if(ev.firstCopyDestinationIdentity.empty())ev.firstCopyDestinationIdentity=current;
                if(!ev.lastCopyDestinationIdentity.empty()&&ev.lastCopyDestinationIdentity!=current)ev.copyDestinationApiChanges++;
                ev.lastCopyDestinationIdentity=current;ev.copyDestinationDesc=desc;
                const double copyStart=qpc();ctx->CopyResource(currentBack.Get(),actualPrivateRtvResource.Get());frameCopyMs=(qpc()-copyStart)*1000;
                ev.copyCallsTotal++;
                // Release this currentlogicalbuffer reference before DXGIrotates onPresent.
                currentBack.Reset();
            }
            double p0=qpc();hr=swap->Present(cfg.vsync,0);double completed=qpc();check(hr,"Present");
            if(hr==DXGI_STATUS_OCCLUDED){ev.occluded++;Sleep(10);}else if(completed>=measureStart){ev.stage="measuring";ev.frames++;ev.drawCalls+=15;if(cfg.privateCopy){ev.copyCallsMeasured++;ev.copyMs.push_back(frameCopyMs);}ev.presentMs.push_back((completed-p0)*1000);if(previous)ev.frameMs.push_back((completed-previous)*1000);previous=completed;ev.measuredSeconds=completed-measureStart;}
            if(completed-lastCheckpoint>=1){std::wostringstream title;title<<L"Native D3D11 copy probe | "<<std::fixed<<std::setprecision(1)<<(ev.measuredSeconds>0?ev.frames/ev.measuredSeconds:0)<<L" presents/s | 15 rotating cubes";SetWindowTextW(window,title.str().c_str());writeEvidence(cfg,ev);lastCheckpoint=completed;}
        }
        ev.removedReason=device->GetDeviceRemovedReason();if(FAILED(ev.removedReason))throw std::runtime_error("Device removed "+hexhr(ev.removedReason));
        if(!previouslyForeground){double last=qpc();ev.foregroundLostSeconds+=last-previousFocusCheck;ev.measurementForegroundLostSeconds+=std::max(0.0,std::min(last,end)-std::max(previousFocusCheck,measureStart));}
        ev.status=ev.exitedEarly?"closed_early":((ev.occluded||ev.minimized||ev.foregroundLostChecks)?"completed_with_visibility_interruptions":"completed");ev.stage="complete";
    }catch(const std::exception& e){ev.errors.push_back(e.what());ev.status="failed";if(device)ev.removedReason=device->GetDeviceRemovedReason();result=1;}
    ev.finish=utcNow();if(outputOwned){try{writeEvidence(cfg,ev);}catch(const std::exception& e){std::cerr<<e.what()<<'\n';result=1;}}else{for(const auto& error:ev.errors)std::cerr<<error<<'\n';}
    if(ctx){ctx->ClearState();ctx->Flush();}if(window&&IsWindow(window))DestroyWindow(window);
    if(done)SetEvent(done);if(watchdog.joinable())watchdog.join();if(done)CloseHandle(done);
    std::cout<<"status="<<ev.status<<" adapter="<<ev.adapter<<" presents="<<ev.frames<<" seconds="<<ev.measuredSeconds<<" fps="<<(ev.measuredSeconds>0?ev.frames/ev.measuredSeconds:0)<<" output="<<utf8(cfg.output)<<'\n';return result;
}
