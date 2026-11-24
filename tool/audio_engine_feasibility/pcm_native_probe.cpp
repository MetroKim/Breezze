// Breezze P0.2. Synthetic PCM only; not OS playback or a hardware soak.
#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <iomanip>
#include <iostream>
#include <stdexcept>
#include <vector>
namespace {
constexpr int Hz=48000, channels=2, frames=256, virtualSeconds=3600;
constexpr double budgetUs=1000000.0*frames/Hz;
using Block=std::array<float,frames*channels>;
class Dsp {
 public:
  // Fixed buffers, no allocation, blocking, I/O or Dart on the render path.
  void render(const float* a,const float* b,float* out,int count,float ga,float gb) noexcept {
    for(int i=0;i<count;++i){
      const int j=i*channels;
      const float l=ga*a[j]+gb*b[j],r=ga*a[j+1]+gb*b[j+1];
      left_+=0.17f*(l-left_);
      right_+=0.17f*(r-right_);
      out[j]=std::clamp(0.96f*left_+0.04f*right_,-1.0f,1.0f);
      out[j+1]=std::clamp(0.96f*right_+0.04f*left_,-1.0f,1.0f);
    }
  }
 private:
  float left_=0,right_=0;
};
void check(bool x,const char* why){if(!x)throw std::runtime_error(why);}
void checkOutput(const Block& x){
  for(float v:x){check(std::isfinite(v),"nonfinite PCM");check(v>=-1.0f&&v<=1.0f,"out-of-range PCM");}
}
}
int main(){
  try{
    Block a{},b{},out{};
    Dsp engine;
    for(int n=0;n<frames;++n){
      const double t=static_cast<double>(n)/Hz;
      a[n*2]=static_cast<float>(0.4*std::sin(2*3.141592653589793*440*t));
      a[n*2+1]=static_cast<float>(0.4*std::sin(2*3.141592653589793*660*t));
      b[n*2]=static_cast<float>(0.3*std::sin(2*3.141592653589793*880*t));
      b[n*2+1]=static_cast<float>(0.3*std::sin(2*3.141592653589793*220*t));
    }
    engine.render(a.data(),b.data(),out.data(),frames,0.8f,0.6f);
    checkOutput(out);
    check(std::any_of(out.begin(),out.end(),[](float x){return x!=0.0f;}),"nonzero input became silent");
    Block zero{};
    Dsp fresh;
    fresh.render(zero.data(),zero.data(),out.data(),frames,1.0f,0.0f);
    check(std::all_of(out.begin(),out.end(),[](float x){return x==0.0f;}),"silence invariant");
    std::fill(a.begin(),a.end(),10.0f);
    fresh.render(a.data(),b.data(),out.data(),frames,1.0f,0.0f);
    checkOutput(out);
    for(int n=0;n<frames;++n){
      const double t=n*2.0*3.141592653589793/frames;
      a[n*2]=static_cast<float>(0.4*std::sin(t));
      a[n*2+1]=static_cast<float>(0.35*std::cos(t));
    }
    const int blocks=virtualSeconds*Hz/frames;
    std::vector<double> times;times.reserve(blocks);
    uint64_t checksum=0;int misses=0;
    const auto begin=std::chrono::steady_clock::now();
    for(int n=0;n<blocks;++n){
      const float t=static_cast<float>((n%750)/750.0);
      const float ga=std::cos(t*1.57079632679f),gb=std::sin(t*1.57079632679f);
      const auto started=std::chrono::steady_clock::now();
      engine.render(a.data(),b.data(),out.data(),frames,ga,gb);
      const double microseconds=std::chrono::duration<double,std::micro>(
        std::chrono::steady_clock::now()-started).count();
      times.push_back(microseconds);
      if(microseconds>budgetUs)++misses;
      checksum+=static_cast<uint64_t>((out[(n%frames)*channels]+1.0f)*1000000.0f);
    }
    const double wall=std::chrono::duration<double>(std::chrono::steady_clock::now()-begin).count();
    checkOutput(out);
    std::sort(times.begin(),times.end());
    check(checksum>0,"checksum");
    check(virtualSeconds/wall>=2.0,"offline throughput <2x");
    std::cout<<std::fixed<<std::setprecision(3)
      <<"{\"probe\":\"breezze-p0-native-pcm\",\"result\":\"PASS\""
      <<",\"sample_rate_hz\":"<<Hz
      <<",\"channels\":"<<channels
      <<",\"frames_per_callback\":"<<frames
      <<",\"virtual_audio_seconds\":"<<virtualSeconds
      <<",\"total_callbacks\":"<<blocks
      <<",\"callback_budget_us\":"<<budgetUs
      <<",\"callback_p50_us\":"<<times[blocks/2]
      <<",\"callback_p99_us\":"<<times[static_cast<int>(blocks*0.99)]
      <<",\"callback_max_us\":"<<times.back()
      <<",\"deadline_misses_on_ci_host\":"<<misses
      <<",\"offline_throughput_x\":"<<virtualSeconds/wall
      <<",\"wall_clock_seconds\":"<<wall
      <<",\"checksum\":"<<checksum
      <<",\"claims_real_device_soak\":false"
      <<",\"claims_authorized_stream_pcm\":false}\n";
  }catch(const std::exception& e){std::cerr<<"FAIL: "<<e.what()<<'\n';return 1;}
}
