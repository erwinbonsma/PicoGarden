pico-8 cartridge // http://www.pico-8.com
version 32
__lua__
bit0=0x0.0001

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
 return (($a>>(x%bpu))&0x1)==0x1
end

function bitgrid:set(x,y)
 local a=self:_address(x,y)
 poke4(a,$a|(0x1<<(x%bpu)))
end

function bitgrid:clr(x,y)
 local a=self:_address(x,y)
 poke4(a,$a&~(0x1<<(x%bpu)))
end

function bitgrid:reset()
 memset(
  self.a0,0,self.height*self.upr
 )
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
 printh("upr="..o.upr.."/"..
  o.bitgrid.upr)
 printh("bpr"..o.bpr)
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
 --todo
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
-->8
function _init()
 --bg=bitgrid:new(0x4400,80,64)
 gol=ca:new(0x4400,30,8)--80,64)
 cx=0
 cy=0
end

function _draw()
 cls()

 rectfill(
  cx+23,cy+31,cx+25,cy+33,10
 )
 
 color()
 for x=0,gol.w-1 do
  for y=0,gol.h-1 do
   if gol:get(x,y) then
    pset(x+24,y+32)
   end
  end
 end
end

function _update()
 if btnp(⬆️) then
  cy=(cy+63)%64
 end
 if btnp(⬇️) then
  cy=(cy+1)%64
 end
 if btnp(⬅️) then
  cx=(cx+79)%80
 end
 if btnp(➡️) then
  cx=(cx+1)%80
 end
 if btnp(❎) then
  if gol:get(cx,cy) then
   gol:clr(cx,cy)
  else
   gol:set(cx,cy)
  end
 end
 if btnp(🅾️) then
  gol:step()
 end
end
__gfx__
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00700700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00077000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00077000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00700700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
