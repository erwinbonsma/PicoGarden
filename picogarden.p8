pico-8 cartridge // http://www.pico-8.com
version 32
__lua__
bit0=0x0.0001

function count_bits(val)
 assert(val==flr(val))
 local nbits=0
 while val!=0 do
  if val&0x1==0x1 then
   nbits+=1
   val&=~0x1
  end
  val>>>=1
 end

 return nbits
end

-- 3x17=51 bytes
mem_cagrid_work=0x8000

-- bits per unit: the number of
-- bits stored per memory unit
-- in bit_grid
bpu=32

-- bits per unit in ca
bpu_ca=bpu-1

bitgrid={}
function bitgrid:new(
 address,width,height
)
 local o=setmetatable({},self)
 self.__index=self

 o.a0=address
 o.w=width
 o.h=height

 local x_bits=o.w%bpu
 local bits_per_row=o.w
 if x_bits>0 then
  bits_per_row+=bpu-x_bits
 end
 --units per row
 o.upr=bits_per_row\bpu
 
 return o
end

function bitgrid:_address(x,y)
 return self.a0+4*(
  x\bpu+y*self.upr
 )
end

function bitgrid:get(x,y)
 local a=self:_address(x,y)
 return (
  ($a>>>(x%bpu))&bit0
 )==bit0
end

function bitgrid:set(x,y)
 local a=self:_address(x,y)
 poke4(a,$a|(bit0<<(x%bpu)))
end

function bitgrid:clr(x,y)
 local a=self:_address(x,y)
 poke4(a,$a&~(bit0<<(x%bpu)))
end

function bitgrid:reset()
 memset(
  self.a0,0,self.h*self.upr*4
 )
end

function bitgrid:randomize()
 local a=self.a0
 local n=self.h*self.upr*4
 for i=1,n do
  poke(a,flr(rnd(256)))
  a+=1
 end
end

ca_specs={}
function ca_specs:new(
 width,height,wraps
)
 local o=setmetatable({},self)
 self.__index=self

 o.w=width
 o.h=height
 o.wraps=wraps

 -- units per row
 o.upr=width\bpu_ca+1
 -- bytes per row
 o.bpr=4*o.upr

 -- bit grid dimensions. it is
 -- larger due to border and
 -- duplicate bit at unit
 -- boundary
 o.bg_w=o.upr*bpu
 o.bg_h=height+2

 -- masks with valid bits
 local mask_c=~(bit0<<bpu_ca)
 local mask_l=mask_c&~bit0
 local mask_r=mask_c
 if (ca.upr==1) mask_r=mask_l

 -- #bits in last unit
 local nblu=width%bpu_ca+1
 if nblu<bpu then
  mask_r&=~0>>>(bpu-nblu)
 end

 o.mask_c=mask_c
 o.mask_r=mask_r
 o.mask_l=mask_l

 return o
end

ca={}
ca_rows=0x4300
function ca:new(address,specs)
 local o=setmetatable({},self)
 self.__index=self

 o.specs=specs
 o.bitgrid=bitgrid:new(
  address,specs.bg_w,specs.bg_h
 )
 o.steps=0

 return o
end

function ca:reset()
 self.steps=0
 self.bitgrid:reset()
end

function ca:randomize()
 self.bitgrid:randomize()
end

function ca:_set_zeroes_border()
 local bg=self.bitgrid
 local specs=self.specs

 -- top row
 memset(bg.a0,0,specs.bpr)
 -- bottom row
 memset(
  bg.a0+(bg.h-1)*specs.bpr,
  0,specs.bpr
 )
 -- left/right columns
 local bitmask_l=~bit0
 local bitmask_r=~(
  bit0<<((specs.w+1)%bpu_ca)
 )
 local a=bg.a0+specs.bpr
 for i=1,specs.h do
  poke4(a,$a&bitmask_l)
  a+=specs.bpr-4
  poke4(a,$a&bitmask_r)
  a+=4
 end
end

function ca:_set_wrapping_border()
 local bg=self.bitgrid
 local specs=self.specs

 -- left and right colums
 local sh_l_dst=0
 local sh_l_src=1
 local sh_r_dst=specs.w%bpu_ca+1
 local sh_r_src=sh_r_dst-1
 local al=bg.a0+specs.bpr
 local ar=bg.a0+specs.bpr*2-4
 for i=1,specs.h do
  -- clear old bit
  poke4(
   al,$al&~(bit0<<sh_l_dst)
  )
  poke4(
   ar,$ar&~(bit0<<sh_r_dst)
  )

  -- copy wrapped bit
  poke4(
   al,
   $al|(($ar&(bit0<<sh_r_src))
        >>>(sh_r_src-sh_l_dst))
  )
  poke4(
   ar,
   $ar|(($al&(bit0<<sh_l_src))
        <<(sh_r_dst-sh_l_src))
  )

  al+=specs.bpr
  ar+=specs.bpr
 end

 -- top row
 memcpy(
  bg.a0,
  bg.a0+(bg.h-2)*specs.bpr,
  specs.bpr
 )
 -- bottom row
 memcpy(
  bg.a0+(bg.h-1)*specs.bpr,
  bg.a0+specs.bpr,
  specs.bpr
 )
end

function ca:_set_border()
 if self.specs.wraps then
  self:_set_wrapping_border()
 else
  self:_set_zeroes_border()
 end
end

function ca:_restore_right_bits()
 local bg=self.bitgrid
 local specs=self.specs

 local a=bg.a0+specs.bpr
 local a_max=a+specs.bpr*specs.h
 local mask=~(bit0<<bpu_ca)
 while a<a_max do
  -- clear bit
  local v=$a&mask
  -- copy value from next unit
  v|=($(a+4)&bit0)<<bpu_ca
  poke4(a,v)
  a+=4
 end
end

function ca:step()
 local bg=self.bitgrid
 local specs=self.specs

 local r0=ca_rows
 local r1=r0+specs.bpr
 local r2=r1+specs.bpr

 self.steps+=1

 self:_restore_right_bits()
 self:_set_border()

 local a=bg.a0
 -- init row #0 and row #1
 memcpy(r0,a,specs.bpr*2)

 a+=specs.bpr
 for row=1,specs.h do
  -- init row #2
  memcpy(
   r2,a+specs.bpr,specs.bpr
  )

  local abc_sum_prev=0
  local abc_car_prev=0

  for col=0,specs.bpr-1,4 do
   local above=$(r0+col)
   local below=$(r2+col)
   local currn=$(r1+col)

   -- above + below
   local ab_sum=above^^below
   local ab_car=above&below

   -- above + below + current
   local abc_sum=currn^^ab_sum
   local abc_car=currn&ab_sum|ab_car

   -- sum of bit0 (sum of sums)
   local l=abc_sum<<1
    |abc_sum_prev>>>(bpu_ca-1)
   local r=abc_sum>>>1
   local lr=l^^r
   local sum0=lr^^ab_sum
   local car0=l&r|lr&ab_sum

   -- sum of bit1 (sum of carry's)
   l=abc_car<<1
    |abc_car_prev>>>(bpu_ca-1)
   r=abc_car>>>1
   lr=l^^r
   local sum1=lr^^ab_car
   local car1=l&r|lr&ab_car

   poke4(a,
    (currn|sum0)
    &(car0^^sum1)
    &~car1
   )
   a+=4

   abc_sum_prev=abc_sum
   abc_car_prev=abc_car
  end

  local rtmp=r0
  r0=r1
  r1=r2
  r2=rtmp
 end
end

function ca:_address(x,y)
 return (
  self.bitgrid.a0
  +4*((x+1)\bpu_ca)
  +self.specs.bpr*(y+1)
 )
end

function ca:get(x,y)
 return (
  $(self:_address(x,y))
  >>((x+1)%bpu_ca)
 )&bit0==bit0
end

function ca:clr(x,y)
 local a=self:_address(x,y)
 poke4(
  a,$a&~(bit0<<((x+1)%bpu_ca))
 )
end

function ca:set(x,y)
 local a=self:_address(x,y)
 poke4(
  a,$a|(bit0<<((x+1)%bpu_ca))
 )
end

-->8
bitcounter={}

function bitcounter:new()
 local o=setmetatable({},self)
 self.__index=self

 o.lookup={}
 for i=0,255 do
  o.lookup[i]=count_bits(i)
 end

 return o
end

function bitcounter:count_bits(
 bg
)
 local nbits=0
 local a=bg.a0
 local amax=a+bg.h*bg.upr*4
 local lookup=self.lookup

 while a<amax do
  nbits+=lookup[@a]
  a+=1
 end

 return nbits
end

function bitcounter:count_ca_bits(
 ca,bg
)
 local specs=ca.specs

 if bg==nil then
  bg=ca.bitgrid
 else
  assert(specs.bg_w==bg.w)
  assert(specs.bg_h==bg.h)
 end

 local nbits=0
 local i=0
 local a=bg.a0+specs.bpr
 local amax=a+specs.h*specs.bpr
 local lookup=self.lookup
 while a<amax do
  local v
  if i==0 then
   v=$a&specs.mask_l
   i=1
  elseif i==specs.upr-1 then
   v=$a&specs.mask_r
   i=0
  else
   v=$a&specs.mask_c
   i+=1
  end

  nbits+=lookup[v&0xff]
  nbits+=lookup[(v>>>8)&0xff]
  nbits+=lookup[(v<<8)&0xff]
  nbits+=lookup[(v<<16)&0xff]

  a+=4
 end

 return nbits
end

decay={}

function decay:new(ca)
 local o=setmetatable({},self)
 self.__index=self

 o.ca=ca
 o.count=-1

 return o
end

function decay:find_target()
 local y=flr(rnd(self.ca.h))
 local x=flr(rnd(self.ca.w))

 -- find non-empty unit
 -- todo
end

function decay:update()
 if self.count==-1 then
  self:find_target()
 else
  if
   self.ca:get(self.x,self.y)
  then
   self.count+=1
   if self.count==100 then
    self:destroy_target()
   end
  else
   self.count=-1
  end
 end
end
-->8
function init_expand()
 local expand={}

 for i=0,255 do
  local x=i>>16
  x=(x|x<<12)&0x000f.000f
  x=(x|x<< 6)&0x0303.0303
  x=(x|x<< 3)&0x1111.1111
  expand[i]=x
 end

 return expand
end

function _init()
 local specs=ca_specs:new(
  80,64,true
 )

 state={}
 state.gols={}
 for i=1,4 do
  local gol=ca:new(
   0x4400+i*16*64,specs
  )
  --gol:reset()
  gol:randomize()
  add(state.gols,gol)
 end
 state.cx=0
 state.cy=0
 state.play=false
 state.t=0
 state.wait=0
 state.viewmask=0xf

 expand=init_expand()

 state.bitcounter=bitcounter:new()
end

function draw_gol(i,gol)
 local d0=0x6000+12+64*32
 local bg=gol.bitgrid
 for y=0,63 do
  local d=d0+y*64
  local rb=80
  local a
   =bg.a0+(y+1)*gol.specs.bpr
  local rbpu=bpu_ca
  while rb>0 do
   local v
   local nb=min(rbpu,rb)
   if rbpu>=8 then
    v=(
     $a>>>(bpu_ca-rbpu)
    )&0x0.00ff
    rbpu-=8
   else
    v=$a>>>(bpu_ca-rbpu)
    a+=4
    v|=($a<<rbpu)&0x0.00ff
    rbpu=bpu_ca-(8-rbpu)
   end
   rb-=8
   v=v<<16
   poke4(
    d,$d|(expand[v]<<(i-1))
   )
   d+=4
  end
  --for x=0,79 do
  -- if gols[i]:get(x,y) then
  --  pset(x+24,y+64,7)
  -- end
  --end
 end
end

function _draw()
 cls()

 color(6)
 for i=0,10 do
  --line(24+i*8,32,24+i*8,95)
 end

 for i,gol in pairs(state.gols) do
  if
   state.viewmask&(0x1<<(i-1))!=0
  then
   draw_gol(i,gol)
  end
	 local ncells=state.bitcounter
   :count_ca_bits(gol)
  local ncells2=state.bitcounter
   :count_bits(gol.bitgrid)
  print(
   "steps="..gol.steps
   ..", cells="..ncells
   .."/"..ncells2,
   0,60+32+i*6,1<<(i-1)
  )
 end

 if not state.play then
  color(10)
  local x=state.cx+25
  local y=state.cy+32
  pset(x-1,y)
  pset(x+1,y)
  pset(x,y-1)
  pset(x,y+1)
 end
end

function _update()
 if btnp(⬆️) then
  if state.play then
   if (state.wait>0) state.wait-=1
  else
   state.cy=(state.cy+63)%64
  end
 end
 if btnp(⬇️) then
  if state.play then
   state.wait+=1
  else
   state.cy=(state.cy+1)%64
  end
 end
 if btnp(⬅️) then
  if state.play then
   state.viewmask=
    (state.viewmask+15)%16
  else
   state.cx=(state.cx+79)%80
  end
 end
 if btnp(➡️) then
  if state.play then
   state.viewmask=
    (state.viewmask+1)%16
  else
   state.cx=(state.cx+1)%80
  end
 end
 local gol=state.gols[1]
 if btnp(❎) then
  if gol:get(state.cx,state.cy) then
   gol:clr(state.cx,state.cy)
  else
   gol:set(state.cx,state.cy)
  end
 end
 if btnp(🅾️) then
  state.play=not state.play
 end

 if state.play then
  state.t+=1
  if state.t%(0x1<<state.wait)==0 then
   for gol in all(state.gols) do
    gol:step()
   end
  end
 end
end
__gfx__
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00700700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00077000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00077000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00700700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
