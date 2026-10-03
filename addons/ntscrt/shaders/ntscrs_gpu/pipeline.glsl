#[compute]
#version 450
// Translation of ntsc-rs add90f5bf1bf7e3c573e4e945a16f44a82941b51.
// ntsc.rs, filter.rs, shift.rs, yiq_fielding.rs: Apache-2.0.
// noise simplex/grid/hash adapted upstream from Ralith/Clatter (MIT/Apache-2.0/zlib).
// Modified for Godot compute: float planes, one serial invocation per scanline.
layout(local_size_x=1,local_size_y=1,local_size_z=1) in;
layout(set=0,binding=0,rgba8) uniform readonly image2D input_image;
layout(set=0,binding=1,rgba8) uniform writeonly image2D output_image;
layout(set=0,binding=2,std430) readonly buffer Src { float src[]; };
layout(set=0,binding=3,std430) buffer Dst { float dst[]; };
layout(set=0,binding=4,std430) readonly buffer Settings { float settings[]; };
layout(set=0,binding=5,rgba8) uniform readonly image2D history_image;
layout(push_constant,std430) uniform Params { int width; int height; int frame; int stage; uint seed; int pad0; int pad1; int pad2; } pc;
const float PI=3.14159265358979323846;
const float RATE=(315000000.0/88.0)*4.0;
#define chroma_lowpass_in settings[0]
#define composite_preemphasis settings[1]
#define video_scanline_phase_shift settings[2]
#define video_scanline_phase_shift_offset settings[3]
#define composite_noise_intensity settings[4]
#define chroma_noise_intensity settings[5]
#define snow_intensity settings[6]
#define chroma_phase_noise_intensity settings[7]
#define chroma_delay_horizontal settings[8]
#define chroma_delay_vertical settings[9]
#define chroma_lowpass_out settings[10]
#define head_switching settings[11]
#define head_switching_height settings[12]
#define head_switching_offset settings[13]
#define head_switching_horizontal_shift settings[14]
#define tracking_noise settings[15]
#define tracking_noise_height settings[16]
#define tracking_noise_wave_intensity settings[17]
#define tracking_noise_snow_intensity settings[18]
#define ringing settings[19]
#define ringing_frequency settings[20]
#define ringing_power settings[21]
#define ringing_scale settings[22]
#define vhs_settings settings[23]
#define vhs_tape_speed settings[24]
#define vhs_chroma_vert_blend settings[25]
#define vhs_chroma_loss settings[26]
#define vhs_sharpen settings[27]
#define vhs_edge_wave settings[28]
#define vhs_edge_wave_speed settings[29]
#define use_field settings[30]
#define tracking_noise_noise_intensity settings[31]
#define bandwidth_scale settings[32]
#define chroma_demodulation settings[33]
#define snow_anisotropy settings[34]
#define tracking_noise_snow_anisotropy settings[35]
#define random_seed settings[36]
#define chroma_phase_error settings[37]
#define input_luma_filter settings[38]
#define vhs_edge_wave_enabled settings[39]
#define vhs_edge_wave_frequency settings[40]
#define vhs_edge_wave_detail settings[41]
#define chroma_noise settings[42]
#define chroma_noise_frequency settings[43]
#define chroma_noise_detail settings[44]
#define luma_smear settings[45]
#define filter_type settings[46]
#define vhs_sharpen_enabled settings[47]
#define vhs_sharpen_frequency settings[48]
#define head_switching_start_mid_line settings[49]
#define head_switching_mid_line_position settings[50]
#define head_switching_mid_line_jitter settings[51]
#define composite_noise settings[52]
#define composite_noise_frequency settings[53]
#define composite_noise_detail settings[54]
#define luma_noise settings[55]
#define luma_noise_frequency settings[56]
#define luma_noise_intensity settings[57]
#define luma_noise_detail settings[58]
#define vertical_scale settings[59]
#define scale_with_video_size settings[60]
#define scale_settings settings[61]
int w,h,r,base,rows,localrow,fr,field;
float hs,vs;
int at(int plane,int x,int y){return plane*w*h+y*w+x;}
float getd(int plane,int x){return dst[at(plane,x,r)];}
void putd(int plane,int x,float v){dst[at(plane,x,r)]=v;}
float gets(int plane,int x,int y){return src[at(plane,x,y)];}
void context(){
 w=pc.width;h=pc.height;r=int(gl_GlobalInvocationID.x);field=int(use_field);
 if(field==0)field=(pc.frame&1)==0?2:1;
 base=0;rows=h;localrow=r;fr=pc.frame;
 if(field==1||field==2)rows=field==1?(h+1)/2:max(h/2,1);
 if(field>=4){int first=field==4?(h+1)/2:h/2;bool second=r>=first;base=second?first:0;rows=second?h-first:first;localrow=r-base;fr=pc.frame*2+int(second);}
 hs=1.0;vs=1.0;if(scale_settings!=0.0){float s=scale_with_video_size!=0.0?float(h)/480.0:1.0;hs=bandwidth_scale*s;vs=vertical_scale*s;}
}
int phase(){int mode=int(video_scanline_phase_shift);if(mode==0)return 0;if(mode==2)return (((fr+localrow*2)&2)+int(video_scanline_phase_shift_offset))&3;return (fr+int(video_scanline_phase_shift_offset)+localrow)&3;}
vec2 carrier(int x){int p=x&3;return p==0?vec2(1,0):p==1?vec2(0,1):p==2?vec2(-1,0):vec2(0,-1);}
// 64-bit unsigned arithmetic as two 32-bit limbs, supported by Metal.
uvec2 add64(uvec2 a,uvec2 b){uint l=a.x+b.x;return uvec2(l,a.y+b.y+uint(l<a.x));}
uvec2 shl64(uvec2 a,uint n){if(n==0u)return a;if(n<32u)return uvec2(a.x<<n,(a.y<<n)|(a.x>>(32u-n)));return uvec2(0,a.x<<(n-32u));}
uvec2 shr64(uvec2 a,uint n){if(n==0u)return a;if(n<32u)return uvec2((a.x>>n)|(a.y<<(32u-n)),a.y>>n);return uvec2(a.y>>(n-32u),0);}
uvec2 rot64(uvec2 a,uint n){return shl64(a,n)|shr64(a,64u-n);}
uvec2 mul64(uvec2 a,uvec2 b){uint hi,lo;umulExtended(a.x,b.x,hi,lo);return uvec2(lo,hi+a.x*b.y+a.y*b.x);}
struct Sip {uvec2 v0;uvec2 v1;uvec2 v2;uvec2 v3;uvec2 tail;uint bytes;uint total;};
void round_sip(inout Sip s){s.v0=add64(s.v0,s.v1);s.v1=rot64(s.v1,13u)^s.v0;s.v0=rot64(s.v0,32u);s.v2=add64(s.v2,s.v3);s.v3=rot64(s.v3,16u)^s.v2;s.v0=add64(s.v0,s.v3);s.v3=rot64(s.v3,21u)^s.v0;s.v2=add64(s.v2,s.v1);s.v1=rot64(s.v1,17u)^s.v2;s.v2=rot64(s.v2,32u);}
Sip sipnew(){return Sip(uvec2(0x70736575u,0x736f6d65u),uvec2(0x6e646f6du,0x646f7261u),uvec2(0x6e657261u,0x6c796765u),uvec2(0x79746573u,0x74656462u),uvec2(0),0u,0u);}
void sipword(inout Sip s,uint v){s.tail|=shl64(uvec2(v,0),s.bytes*8u);s.bytes+=4u;s.total+=4u;if(s.bytes==8u){s.v3^=s.tail;round_sip(s);round_sip(s);s.v0^=s.tail;s.tail=uvec2(0);s.bytes=0u;}}
void sip64(inout Sip s,uint v){sipword(s,v);sipword(s,0u);}
uvec2 finish(Sip s){uvec2 b=s.tail|uvec2(0,(s.total&255u)<<24);s.v3^=b;round_sip(s);round_sip(s);s.v0^=b;s.v2.x^=255u;for(int i=0;i<4;i++)round_sip(s);return s.v0^s.v1^s.v2^s.v3;}
Sip seeded(uint pass,bool frame_mix){Sip s=sipnew();sip64(s,pc.seed);sip64(s,pass);if(frame_mix)sip64(s,uint(fr));return s;}
uvec2 seedrow(uint pass,uint row){Sip s=seeded(pass,true);sip64(s,row);return finish(s);}
uvec2 seedint(uint pass,uint index,bool frame_mix){Sip s=seeded(pass,frame_mix);sipword(s,index);return finish(s);}
float sf(uvec2 s){return uintBitsToFloat((s.x>>9)|0x3f800000u)-1.0;}
struct Rng {uvec2 a;uvec2 b;uvec2 c;uvec2 d;};
uvec2 splitmix(inout uvec2 state){state=add64(state,uvec2(0x7f4a7c15u,0x9e3779b9u));uvec2 z=state;z=mul64(z^shr64(z,30u),uvec2(0x1ce4e5b9u,0xbf58476du));z=mul64(z^shr64(z,27u),uvec2(0x133111ebu,0x94d049bbu));return z^shr64(z,31u);}
Rng rngnew(uvec2 seed){Rng g;g.a=splitmix(seed);g.b=splitmix(seed);g.c=splitmix(seed);g.d=splitmix(seed);return g;}
uvec2 next64(inout Rng g){uvec2 res=add64(rot64(add64(g.a,g.d),23u),g.a);uvec2 t=shl64(g.b,17u);g.c^=g.a;g.d^=g.b;g.b^=g.c;g.a^=g.d;g.c^=t;g.d=rot64(g.d,45u);return res;}
float random32(inout Rng g){return float(next64(g).y>>8)*0.000000059604644775390625;}
// f64 geometric decisions evaluated in f32 on Metal; documented numerical limitation.
float random64f(inout Rng g){uvec2 v=next64(g);return float(v.y)*2.3283064365386963e-10+float(v.x>>11)*1.1102230246251565e-16;}
float rangef(inout Rng g,float a,float b){float v=uintBitsToFloat((next64(g).y>>9)|0x3f800000u)-1.0;return v*(b-a)+a;}
void jump(inout Rng g){uvec2 j[4]=uvec2[4](uvec2(0x3cfd0abau,0x180ec6d3u),uvec2(0xf0c9392cu,0xd5a61266u),uvec2(0xe03fc9aau,0xa9582618u),uvec2(0x29b1661cu,0x39abdc45u));Rng z=Rng(uvec2(0),uvec2(0),uvec2(0),uvec2(0));for(int k=0;k<4;k++)for(uint b=0u;b<64u;b++){if((shr64(j[k],b).x&1u)!=0u){z.a^=g.a;z.b^=g.b;z.c^=g.c;z.d^=g.d;}next64(g);}g=z;}
uint hash1(uint v){v=(v^2747636419u)*2654435769u;v=(v^(v>>16))*2654435769u;return (v^(v>>16))*2654435769u;}
float grad1(uint v){uint a=v>>28;float g=float((a&7u)+1u);return (a&8u)==0u?-g:g;}
float simplex1(float x,uint seed){float i=floor(x),a=x-i,b=a-1.0;float ta=fma(-a,a,1.0),tb=fma(-b,b,1.0);ta*=ta;tb*=tb;return fma(ta*ta*grad1(hash1(uint(int(i))^seed)),a,tb*tb*grad1(hash1(uint(int(i)+1)^seed))*b);}
uint hash3(ivec2 p,uint seed){uvec3 v=uvec3(p,seed)*1664525u+1013904223u;v.x+=v.y*v.z;v.y+=v.z*v.x;v.z+=v.x*v.y;v^=v>>16;v.x+=v.y*v.z;v.y+=v.z*v.x;v.z+=v.x*v.y;return v.x;}
float contribution(vec2 p,ivec2 cell,uint seed){uint a=hash3(cell,seed)&7u;vec2 g=a<4u?vec2(1,2):vec2(2,1);if((a&(a<4u?1u:2u))!=0u)g.x=-g.x;if((a&(a<4u?2u:1u))!=0u)g.y=-g.y;float t=max(0.0,fma(-p.y,p.y,fma(-p.x,p.x,0.5)));t*=t;return t*t*dot(g,p);}
float simplex2(vec2 p,uint seed){float f=(sqrt(3.0)-1.0)/2.0,g=(1.0-1.0/sqrt(3.0))/2.0;vec2 c=floor(p+(p.x+p.y)*f);vec2 d=p-(c-(c.x+c.y)*g);ivec2 stepv=d.x>=d.y?ivec2(1,0):ivec2(0,1);return contribution(d,ivec2(c),seed)+contribution(d-vec2(stepv)+g,ivec2(c)+stepv,seed)+contribution(d-1.0+2.0*g,ivec2(c)+1,seed);}
float fbm1(float x,uint seed,int detail){float n=simplex1(x,seed);for(int k=1;k<clamp(detail,1,5);k++){x*=2.0;n+=simplex1(x,seed);}return n;}
void noise_line(int plane,uvec2 seed,float freq,float intensity,int detail){Rng g=rngnew(seed);uint ns=next64(g).y;float off=random32(g)*float(w);for(int x=0;x<w;x++)putd(plane,x,getd(plane,x)+fbm1((off+float(x))*freq,ns,detail)*intensity*0.25);}
void speckles(uvec2 seed,float intensity,float anisotropy){Rng g=rngnew(seed);float logistic=exp((random64f(g)-intensity)/(intensity*(1.0-intensity)*(1.0-anisotropy)));float p=clamp((anisotropy/(1.0+logistic)+intensity*(1.0-anisotropy))*0.125,0.0,1.0);if(!(p>0.0))return;float lam=log(1.0-p);int pixel=-64;while(pixel<w){float gap=floor(log(random64f(g))/lam);if(gap>=float(w-pixel))break;pixel+=int(gap);float len=rangef(g,8.0,64.0)*hs,freq=rangef(g,len*3.0,len*5.0);jump(g);Rng t=g;for(int x=max(0,pixel);x<min(w,pixel+int(ceil(len)));x++){float pos=float(x-pixel),decay=1.0-pos/len;putd(0,x,getd(0,x)+cos(pos*PI/freq)*decay*decay*rangef(t,-1.0,2.0));}pixel++;}}
struct Filter {vec4 b;vec3 a;int n;};
Filter lowpass(float cut,float rate,int kind){float dt=1.0/rate,alpha=dt/(1.0/(cut*2.0*PI)+dt);float d=-(1.0-alpha);if(kind==2)return Filter(vec4(alpha,0,0,0),vec3(d,0,0),2);if(kind==0)return Filter(vec4(alpha*alpha*alpha,0,0,0),vec3(d+d+d,d*d+d*(d+d),d*d*d),4);float om=min(2.0*cut,rate)/rate*PI,si=sin(om),co=cos(om),a=si/(2.0*0.7071067811865476),gain=1.0/(1.0+a);return Filter(vec4((1.0-co)*0.5*gain,(1.0-co)*gain,(1.0-co)*0.5*gain,0),vec3(-2.0*co*gain,(1.0-a)*gain,0),3);}
Filter notch(float freq,float q){float gain=1.0/(1.0+tan(freq/q*PI*0.5));return Filter(vec4(gain,-2.0*cos(freq*PI)*gain,gain,0),vec3(-2.0*cos(freq*PI)*gain,2.0*gain-1.0,0),3);}
Filter scaled(Filter f,float scale){f.b[0]=scale*f.b[0]+(1.0-scale);for(int k=1;k<f.n;k++)f.b[k]=scale*f.b[k]+(1.0-scale)*f.a[k-1];return f;}
void filt(int plane,Filter f,bool initial,int delay){vec4 z=vec4(0);if(initial){float value=getd(plane,0),bs=0.0,asum=1.0,cs=0.0;for(int k=1;k<f.n;k++){bs+=f.b[k]-f.a[k-1]*f.b[0];asum+=f.a[k-1];}z[0]=bs/asum;asum=1.0;for(int k=1;k<f.n-1;k++){asum+=f.a[k-1];cs+=f.b[k]-f.a[k-1]*f.b[0];z[k]=(asum*z[0]-cs)*value;}z[0]*=value;}for(int x=0;x<w+delay;x++){float samplev=getd(plane,min(x,w-1));float result=z[0]+f.b[0]*samplev;for(int k=0;k<f.n-1;k++)z[k]=z[k+1]+f.b[k+1]*samplev-f.a[k]*result;if(x>=delay)putd(plane,x-delay,result);}}
void chroma_lowpass(int mode){if(mode==0)return;int type=int(filter_type);filt(1,lowpass(mode==2?1300000.0:2600000.0,RATE*hs,type),false,mode==2?2:1);filt(2,lowpass(mode==2?600000.0:2600000.0,RATE*hs,type),false,mode==2?4:1);}
float shifted_d(int plane,int x,int shift_int,float frac,float bound){int left=x-shift_int-1,right=left+1;float a=left>=0&&left<w?getd(plane,left):bound,b=right>=0&&right<w?getd(plane,right):bound;return a*frac+b*(1.0-frac);}
void shiftrow(int plane,float shift,bool extend,int start){int si=int(shift)-(shift<0.0?1:0);float f=shift<0.0?1.0-abs(shift-trunc(shift)):fract(shift);float bound=extend?getd(plane,si>=0?0:w-1):0.0;if(si>=0){for(int x=w-1;x>=start;x--)putd(plane,x,shifted_d(plane,x,si,f,bound));}else{for(int x=start;x<w;x++)putd(plane,x,shifted_d(plane,x,si,f,bound));}}
void copyrow(){for(int p=0;p<3;p++)for(int x=0;x<w;x++)putd(p,x,gets(p,x,r));}
void encode(){for(int x=0;x<w;x++){int y=r;if(field==1||field==2)y=min(h-1,r*2+(field==2?1:0));else if(field>=4){int parity=field==4?int(base!=0):int(base==0);y=min(h-1,localrow*2+parity);}vec3 rgb=imageLoad(input_image,ivec2(x,y)).rgb;putd(0,x,dot(rgb,vec3(.299,.587,.114)));putd(1,x,dot(rgb,vec3(.5959,-.2746,-.3213)));putd(2,x,dot(rgb,vec3(.2115,-.5227,.3112)));}}
void composite(){copyrow();int mode=int(input_luma_filter);if(mode==1&&w>=2){vec4 queue=vec4(16.0/255.0,16.0/255.0,getd(0,0),getd(0,1));float sum=queue.x+queue.y+queue.z+queue.w;float last=getd(0,w-1);for(int x=0;x<w;x++){float c=x<w-2?getd(0,x+2):last;sum-=queue[x&3];queue[x&3]=c;sum+=c;putd(0,x,sum*.25);}}else if(mode==2)filt(0,notch(.5,2.0),true,0);
 chroma_lowpass(int(chroma_lowpass_in));int ph=phase();for(int x=0;x<w;x++)putd(0,x,getd(0,x)+dot(vec2(getd(1,x),getd(2,x)),carrier(x+ph)));
 if(composite_preemphasis!=0.0)filt(0,scaled(lowpass((315000000.0/88.0/2.0)*hs,RATE*hs,2),-composite_preemphasis),false,0);
 if(composite_noise!=0.0)noise_line(0,seedrow(0u,uint(localrow)),composite_noise_frequency/hs,composite_noise_intensity,int(composite_noise_detail));
 if(snow_intensity>0.0&&hs>0.0)speckles(seedrow(6u,uint(localrow)),snow_intensity*.01,snow_anisotropy);
 if(head_switching!=0.0){int count=int(round(max(0.0,head_switching_height)*vs)),off=int(round(max(0.0,head_switching_offset)*vs));int affected=count-off;if(off<=count&&localrow>=max(rows-affected,0)&&affected>0){int index=rows-localrow;float shift=(head_switching_horizontal_shift*pow(float(index+off)/float(count),1.5)+sf(seedrow(2u,uint(index)))-.5)*hs;int start=0;if(index==affected&&head_switching_start_mid_line!=0.0){float jitter=(.5*(sf(seedint(8u,0u,true))+sf(seedint(8u,1u,true)))-.5)*head_switching_mid_line_jitter;start=max(0,int(float(w)*(head_switching_mid_line_position+jitter)));}if(start<=w){shiftrow(0,shift,false,start);if(index==affected&&head_switching_start_mid_line!=0.0){float len=16.0*hs,tint=(sf(seedint(8u,0u,true))+.5)*.5;for(int x=start;x<min(w,start+int(ceil(len)));x++){float d=1.0-float(x-start)/len;putd(0,x,getd(0,x)+d*d*d*tint);}}}}}
 if(tracking_noise!=0.0){int count=int(round(max(0.0,tracking_noise_height)*vs)),start=max(rows-count,0);if(count>0&&localrow>=start){int index=localrow-start+max(count-rows,0);float scale=float(index)/float(count);float off=sf(seedint(3u,1u,true))*float(rows);uint ns=seedint(3u,0u,true).x;float noise=simplex1((off+float(localrow-start))*.5,ns);shiftrow(0,noise*scale*tracking_noise_wave_intensity*.25*hs,false,0);Sip s=seeded(3u,true);sipword(s,2u);sip64(s,uint(index));uvec2 seed=finish(s);noise_line(0,seed,.25/hs,scale*scale*tracking_noise_noise_intensity*4.0,1);speckles(seed,tracking_noise_snow_intensity*scale*scale,tracking_noise_snow_anisotropy);}}
}
void demodulate(){copyrow();int mode=int(chroma_demodulation);if(rows==1&&mode>=2)mode=1;
 if(mode==1)filt(0,notch(.5,2.0),false,0);else for(int x=0;x<w;x++){float v=gets(0,x,r);if(mode==0)v=((x==0?16.0/255.0:gets(0,x-1,r))+v+gets(0,min(x+1,w-1),r)+gets(0,min(x+2,w-1),r))*.25;else{int prev=base+(localrow==0?1:localrow-1);if(mode==2)v=(gets(0,x,prev)+v)*.5;else{int next=base+(localrow==rows-1?rows-2:localrow+1);v=v*.5+gets(0,x,prev)*.25+gets(0,x,next)*.25;}}putd(0,x,v);}
 int ph=phase();for(int x=0;x<w;x++){vec2 iq=-(getd(0,x)-gets(0,x,r))*carrier(x+ph);if(x+1<w)iq-=.5*(getd(0,x+1)-gets(0,x+1,r))*carrier(x+1+ph);if(x>0)iq-=.5*(getd(0,x-1)-gets(0,x-1,r))*carrier(x-1+ph);putd(1,x,iq.x);putd(2,x,iq.y);}
}
void rotate_iq(float turns){float a=turns*2.0*PI,c=cos(a),s=sin(a);for(int x=0;x<w;x++){float i=getd(1,x),q=getd(2,x);putd(1,x,i*c-q*s);putd(2,x,i*s+q*c);}}
void postdemod(){copyrow();if(luma_smear>0.0)filt(0,lowpass(exp2(-4.0*luma_smear)*.25,hs,2),false,0);if(ringing!=0.0)filt(0,scaled(notch(clamp(ringing_frequency/hs,0.0,1.0),ringing_power),ringing_scale),true,1);if(luma_noise!=0.0)noise_line(0,seedrow(10u,uint(localrow)),luma_noise_frequency/hs,luma_noise_intensity,int(luma_noise_detail));if(chroma_noise!=0.0){noise_line(1,seedrow(1u,uint(localrow)),chroma_noise_frequency/hs,chroma_noise_intensity,int(chroma_noise_detail));noise_line(2,seedrow(9u,uint(localrow)),chroma_noise_frequency/hs,chroma_noise_intensity,int(chroma_noise_detail));}if(chroma_phase_error>0.0)rotate_iq(chroma_phase_error);if(chroma_phase_noise_intensity>0.0)rotate_iq((sf(seedrow(4u,uint(localrow)))-.5)*2.0*chroma_phase_noise_intensity);}
void delay_chroma(){copyrow();int delta=int(round(chroma_delay_vertical*vs));float shift=chroma_delay_horizontal*hs;int si=int(shift)-(shift<0.0?1:0);float f=shift<0.0?1.0-abs(shift-trunc(shift)):fract(shift);int y=localrow-delta;for(int p=1;p<3;p++)for(int x=0;x<w;x++){float value=0.0;if(y>=0&&y<rows){int l=x-si-1,rr=l+1;float a=l>=0&&l<w?gets(p,l,base+y):0.0,b=rr>=0&&rr<w?gets(p,rr,base+y):0.0;value=a*f+b*(1.0-f);}putd(p,x,value);}}
void vhs(){copyrow();if(vhs_settings==0.0)return;if(vhs_edge_wave_enabled!=0.0&&vhs_edge_wave>0.0){uint seed=seedint(5u,0u,false).x;float offset=sf(seedint(5u,1u,false))*float(rows);vec2 pos=vec2(offset+float(localrow),float(fr)*vhs_edge_wave_speed)*(vhs_edge_wave_frequency/vs);float n=simplex2(pos,seed),amp=.7071067811865476;for(int j=1;j<clamp(int(vhs_edge_wave_detail),1,5);j++){pos*=2.0;n+=amp*simplex2(pos,seed);amp*=.7071067811865476;}for(int p=0;p<3;p++)shiftrow(p,n/.022*vhs_edge_wave*.5*hs,true,0);}
 int tape=int(vhs_tape_speed),kind=int(filter_type);float lcut=tape==1?2400000.0:tape==2?1900000.0:1400000.0,ccut=tape==1?320000.0:tape==2?300000.0:280000.0;int delay=int(round(float(tape+3)*hs));if(tape!=0){filt(0,lowpass(lcut,RATE*hs,kind),false,0);filt(1,lowpass(ccut,RATE*hs,kind),false,delay);filt(2,lowpass(ccut,RATE*hs,kind),false,delay);filt(0,scaled(lowpass(lcut,RATE*hs,2),-1.6),false,0);}
 if(vhs_chroma_loss>0.0){Rng g=rngnew(finish(seeded(7u,true)));int row=0;float lam=log(1.0-vhs_chroma_loss);while(row<=localrow){float gap=floor(log(random64f(g))/lam);if(gap>float(localrow-row))break;row+=int(gap);if(row==localrow){for(int x=0;x<w;x++){putd(1,x,0.0);putd(2,x,0.0);}break;}row++;}}
 if(tape!=0&&vhs_sharpen_enabled!=0.0)filt(0,scaled(lowpass(lcut*(kind==0?4.0:1.0)*vhs_sharpen_frequency,RATE*hs,kind),-vhs_sharpen*2.0*vhs_sharpen_frequency),false,0);
}
void vertblend(){copyrow();if(vhs_chroma_vert_blend!=0.0)for(int p=1;p<3;p++)for(int x=0;x<w;x++)putd(p,x,(gets(p,x,r)+(localrow==0?0.0:gets(p,x,r-1)))*.5);}
void decode(){for(int x=0;x<w;x++){if(pc.pad0!=0&&(field==1||field==2)&&(r&1)!=(field-1)){imageStore(output_image,ivec2(x,r),imageLoad(history_image,ivec2(x,r)));continue;}int y=r;vec3 yiq;bool bob=false;int y2=0;if(field==1||field==2){int count=field==1?(h+1)/2:max(h/2,1);y=min(r/2,count-1);int parity=field==1?0:1;bob=(r&1)!=parity&&r>0&&r<h-1;if(bob){y=(r-1)/2;y2=(r+1)/2;}}else if(field>=4){int first=field==4?(h+1)/2:h/2;y=r/2+((((r&1)==0)==(field==4))?0:first);y=min(y,h-1);}yiq=vec3(gets(0,x,y),gets(1,x,y),gets(2,x,y));if(bob)yiq=(yiq+vec3(gets(0,x,y2),gets(1,x,y2),gets(2,x,y2)))*.5;vec3 rgb=vec3(yiq.x+.956*yiq.y+.619*yiq.z,yiq.x-.272*yiq.y-.647*yiq.z,yiq.x-1.106*yiq.y+1.703*yiq.z);rgb=floor(clamp(rgb*255.0,0.0,255.0))/255.0;imageStore(output_image,ivec2(x,r),vec4(rgb,1));}}
void main(){context();if(r>=h)return;if(pc.stage==8){decode();return;}if((field==1||field==2)&&r>=rows)return;if(pc.stage==0)encode();else if(pc.stage==1)composite();else if(pc.stage==2)demodulate();else if(pc.stage==3)postdemod();else if(pc.stage==4)delay_chroma();else if(pc.stage==5)vhs();else if(pc.stage==6)vertblend();else if(pc.stage==7){copyrow();chroma_lowpass(int(chroma_lowpass_out));}}
