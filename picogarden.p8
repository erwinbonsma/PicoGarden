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

ca={}
ca_rows=0x4300
function ca:new(
 address,width,height,wraps
)
 local o=setmetatable({},self)
 self.__index=self

 -- units per row
 o.upr=width\bpu_ca+1
 -- bytes per row
 o.bpr=4*o.upr
 o.bitgrid=bitgrid:new(
  address,o.upr*bpu,height+2
 )
 o.w=width
 o.h=height
 o.wraps=wraps
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

 -- top row
 memset(
  bg.a0,0,self.upr*4
 )
 -- bottom row
 memset(
  bg.a0+(bg.h-1)*self.bpr,0,
  self.bpr
 )
 -- left/right columns
 local bitmask_l=~bit0
 local bitmask_r=~(bit0<<(
  (self.w+1)%bpu_ca
 ))
 local a=bg.a0+self.upr*4
 for y=1,self.h-1 do
  poke4(a,$a&bitmask_l)
  a+=self.bpr-4
  poke4(a,$a&bitmask_r)
  a+=4
 end
end

function ca:_set_wrapping_border()
 local bg=self.bitgrid

 -- top row
 memcpy(
  bg.a0,
  bg.a0+(bg.h-2)*self.bpr,
  self.bpr
 )
 -- bottom row
 memcpy(
  bg.a0+(bg.h-1)*self.bpr,
  bg.a0+self.bpr,
  self.bpr
 )

 -- left and right colums
 local sh_l_dst=0
 local sh_l_src=1
 local sh_r_dst=self.w%bpu_ca+1
 local sh_r_src=sh_r_dst-1
 local al=bg.a0+self.bpr
 local ar=bg.a0+self.bpr*2-4
 for i=1,bg.h do
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

  al+=self.bpr
  ar+=self.bpr
 end
end

function ca:_set_border()
 if self.wraps then
  self:_set_wrapping_border()
 else
  self:_set_zeroes_border()
 end
end

function ca:_restore_right_bits()
 local bg=self.bitgrid

 local a=bg.a0+self.bpr
 local a_max=a+self.bpr*self.h
 while a<a_max do
  -- clear bit
  local v=$a&~(bit0<<bpu_ca)
  -- copy value from next unit
  v=v|(($(a+4)&bit0)<<bpu_ca)
  poke4(a,v)
  a+=4
 end
end

function ca:step()
 local bg=self.bitgrid

 local r0=ca_rows
 local r1=r0+self.bpr
 local r2=r1+self.bpr

 self.steps+=1

 self:_restore_right_bits()
 self:_set_border()

 local a=bg.a0
 -- init row #0 and row #1
 memcpy(r0,a,self.bpr*2)

 a+=self.bpr
 for row=1,self.h do
  -- init row #2
  memcpy(r2,a+self.bpr,self.bpr)

  local abc_sum_prev=0
  local abc_car_prev=0

  for col=0,self.bpr-1,4 do
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
  +self.bpr*(y+1)
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
 if bg==nil then
  bg=ca.bitgrid
 else
  assert(ca.bitgrid.w==bg.w)
  assert(ca.bitgrid.h==bg.h)
 end

 local mask_c=~(bit0<<bpu_ca)
 local mask_l=mask_c&~bit0
 local mask_r=mask_c
 if (ca.upr==1) mask_r=mask_l

 -- #bits in last unit
 local nblu=ca.w%bpu_ca+1
 if nblu<bpu then
  mask_r&=~0>>>(bpu-nblu)
 end

 local nbits=0
 local i=0
 local a=bg.a0+ca.bpr
 local amax=a+ca.h*ca.bpr
 local lookup=self.lookup
 while a<amax do
  local v
  if i==0 then
   v=$a&mask_l
   i=1
  elseif i==ca.upr-1 then
   v=$a&mask_r
   i=0
  else
   v=$a&mask_c
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
 state={}
 state.gols={}
 for i=1,4 do
  local gol=ca:new(
   0x4400+i*16*64,80,64,true
  )
  gol:reset()
  --gol:randomize()
  add(state.gols,gol)
 end
 state.cx=0
 state.cy=0
 state.play=false
 state.t=0

 expand=init_expand()

 state.bitcounter=bitcounter:new()
end

function _draw()
 cls()

 color(6)
 for i=0,10 do
  line(24+i*8,32,24+i*8,95)
 end

 local d0=0x6000+12+64*32
 for i,gol in pairs(state.gols) do
  local bg=gol.bitgrid
  for y=0,63 do
   local d=d0+y*64
   local rb=80
   local a=bg.a0+(y+1)*gol.bpr
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
  state.cy=(state.cy+63)%64
 end
 if btnp(⬇️) then
  state.cy=(state.cy+1)%64
 end
 if btnp(⬅️) then
  state.cx=(state.cx+79)%80
 end
 if btnp(➡️) then
  state.cx=(state.cx+1)%80
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
  if state.t%1==0 then
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
