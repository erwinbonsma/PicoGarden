pico-8 cartridge // http://www.pico-8.com
version 32
__lua__
-- 3x17=51 bytes
mem_cagrid_work=0x8000

-- bits per unit: the number of
-- bits stored per memory unit
-- in bit_grid
bpu=32

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
-->8
function _init()
 bg=bitgrid:new(0x4300,80,64)
 cx=0
 cy=0
end

function _draw()
 cls()

 rectfill(
  cx+23,cy+31,cx+25,cy+33,10
 )
 
 color()
 for x=0,79 do
  for y=0,63 do
   if bg:get(x,y) then
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
  bg:clr(cx,cy)
 end
 if btnp(🅾️) then
  bg:set(cx,cy)
 end
end
__gfx__
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00700700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00077000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00077000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00700700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
