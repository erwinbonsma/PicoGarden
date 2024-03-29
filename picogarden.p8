pico-8 cartridge // http://www.pico-8.com
version 41
__lua__
-- pico garden
-- a slow-play screensaver game
-- (c) 2022-2023 eriban

max_cellfind_attempts=32
num_decay_death_ticks=16
mutate_prob=1/512
history_len=80
runsum_len=16
liveliness_limit=50
liveliness_decay=0.99
liveliness_inc=100
decay_level=50
max_wait=6
min_revive_delay=32
cart_version=2

-- colors so that:
-- - the core layer colors are
--   on the power of two indices
-- - the blended colors follow
--   from the core layer colors
--   (as much as possible)
display_palette={
 8,12,14,11,3,13,2,10,
 15,6,5,9,4,1,7,0
}

function color_index(clr)
 for i,c in pairs(display_palette) do
  if (c==clr) return i
 end
end

-- colors after display-palette
-- modification
c_revive_hi=color_index(7)
c_revive_lo=color_index(5)
c_txt=color_index(4)
c_hilo=color_index(9)

bit0=0x0.0001

dirs={
 {dx=1,dy=0},
 {dx=0,dy=1},
 {dx=-1,dy=0},
 {dx=0,dy=-1},
}

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

-- code by felice. see
-- https://www.lexaloffle.com/bbs/?pid=22809
function u32_tostr(v)
 local s=""
 repeat
  local t=v>>>1
  s=(t%0x0.0005<<17)+(v<<16&1)..s
  v=t/5
 until v==0
 return s
end

function cprint(str,y)
 print(str,64-#str*2,y)
end

function rprint(str,x,y)
 print(str,x-#str*4,y)
end

-- returns list of numbers
-- 0..n-1 in random order
function shuffled(n)
 local l={}
 -- populate list
 for i=0,n-1 do
  add(l,i)
 end
 -- shuffle
 for i=1,n do
  local idx=i+flr(rnd(n-i+1))
  local tmp=l[i]
  l[i]=l[idx]
  l[idx]=tmp
 end
 return l
end

flower={}

function flower:new()
 local o=setmetatable({},self)
 self.__index=self

 o.colors=shuffled(4)
 o.sprites=shuffled(11)
 o.frame=0
 o.grow_count=flr(rnd(90))

 return o
end

function flower:update()
 if rnd(256)<128 then
  self.grow_count+=1
  if self.grow_count%60==0 then
   self.frame+=1
  end
 end
end

function flower:draw(x,y)
 for i=1,min(3,self.frame) do
  local s=self.sprites[
   (self.frame-i)%11+1
  ]
  local si=64+(s%8)*2+(s\8)*32
  pal(7,1<<self.colors[
   (self.frame-i)%4+1
  ],0)
  spr(si,x,y,2,2)
 end
 pal(0)
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
  poke(a,
   flr(rnd(256))&flr(rnd(256))
  )
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

function ca:draw(layer_idx)
 local d0=0x6000+12+64*32
 local bg=self.bitgrid
 for y=0,63 do
  local d=d0+y*64
  local rb=80
  local a
   =bg.a0+(y+1)*self.specs.bpr
  local rbpu=bpu_ca-1
  while rb>0 do
   local v
   local nb=min(rbpu,rb)
   if rbpu>=8 then
    v=(
     $a>>>(bpu_ca-rbpu)
    )&0x0.00ff
    rbpu-=8
   else
    v=(
     $a&0x7fff.ffff
    )>>>(bpu_ca-rbpu)
    a+=4
    v|=($a<<rbpu)&0x0.00ff
    rbpu=bpu_ca-(8-rbpu)
   end
   rb-=8
   v<<=16
   poke4(d,$d|(
    expand[v]<<(layer_idx-1)
   ))
   d+=4
  end
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

cellhistory={}

function cellhistory:new()
 local o=setmetatable({},self)
 self.__index=self

 o.counter=bitcounter:new()

 return o
end

function cellhistory:reset()
 self.counts={}
 self.runsum={}
 for i=1,#state.layers do
  self.counts[i]={}
  self.runsum[i]=0
 end

 self.idx=0
 self.np=0
 self:count()
end

function cellhistory:num_cells(
 layer_idx
)
 return self.counts[layer_idx][self.idx]
end

function cellhistory:cell_level(
 layer_idx
)
 return min(4,ceil(
  self.runsum[layer_idx]
  /min(self.np,runsum_len)/100
 ))
end

function cellhistory:total_cells()
 local total=0
 for i=1,#state.layers do
  total+=self.counts[i][self.idx]
 end
 return total
end

function cellhistory:num_empty()
 local num_empty=0
 for i=1,#state.layers do
  if self.counts[i][self.idx]==0
  then
   num_empty+=1
  end
 end
 return num_empty
end

function cellhistory:count()
 self.idx=(self.idx+1)%history_len

 local total=0
 for i,l in pairs(state.layers) do
  local ncells=
	  self.counter:count_ca_bits(l)
  self.counts[i][self.idx]=ncells
  self.runsum[i]+=ncells
  if self.np>=runsum_len then
   local j=(self.idx
            +history_len
            -runsum_len
           )%history_len
   self.runsum[i]-=self.counts[i][j]
  end
  total+=ncells
 end

 self.np=min(self.np+1,history_len)

 return total
end

function cellhistory:draw_plot()
 rectfill(24,32,103,95,0)

 local idx0=(self.idx+1)%history_len
 if self.np<history_len then
  idx0=1
 end

 for i,h in pairs(self.counts) do
  local c=0x1<<(i-1)
  for j=0,self.np-1 do
   local v=h[(idx0+j)%history_len]
   -- use a log-like scale for
   -- the y-axis based on:
   -- y=x*(x+1)/(2*1.6)
   -- the factor 1.6 scales the
   -- axis. fv is obtained from
   -- quadratic formula
   local fv=sqrt(0.25+2*v*1.6)
   local y=95-max(0,min(63,fv-2))
   local x=24+j
   pset(x,y,pget(x,y)|c)
  end
 end
 for i,v in pairs(self.runsum) do
  local c=0x1<<(i-1)
  color(c)
  print(self:cell_level(i),
        79+i*5,33)
 end
end

cellfind={}

function cellfind:new(target_idx)
 local o=setmetatable({},self)
 self.__index=self

 o.target_idx=target_idx

 return o
end

function cellfind:find_target(ca)
 local specs=ca.specs
 for i=1,max_cellfind_attempts do
  local x=flr(rnd(specs.w))
  local y=flr(rnd(specs.h))

  if ca:get(x,y) then
   self.pos={x=x,y=y}
   return true
  end
 end
end

function cellfind:update(cas)
 if self.pos==nil then
  self:find_target(
   cas[self.target_idx]
  )
 end
end

decay=cellfind:new()

function decay:find_target(ca)
 if cellfind.find_target(
  self,ca
 ) then
  self.count=1
  self.mask=0xf
  return true
 end
end

function decay:clear_area(ca)
 local specs=ca.specs
 local pos=self.pos
 for x=pos.x-1,pos.x+1 do
  for y=pos.y-1,pos.y+1 do
   ca:clr(
    (x+specs.w)%specs.w,
    (y+specs.h)%specs.h
   )
  end
 end
end

function decay:destroy(cas)
 local ti=self.target_idx
 for i=1,4 do
  if (
   -- always clear target
   i==ti
   or (
    -- also clear static cells
    -- in other layers
    self.mask&(1<<(i-1))!=0
    and (
     -- as long as layer is
     -- is a direct neighbour
     i%2!=ti%2
     -- or connected via a
     -- static layer
     or count_bits(self.mask)>2
    )
   )
  ) then
   self:clear_area(cas[i])
  end
 end
 self.pos=nil
 state.num_decays+=bit0
end

function decay:update(cas)
 cellfind.update(self,cas)
 if (self.pos==nil) return

 for i,ca in pairs(cas) do
  if not ca:get(
   self.pos.x,self.pos.y
  ) then
   self.mask&=~(1<<(i-1))
  end
 end

 if self.mask&(
  1<<(self.target_idx-1)
 )!=0 then
  self.count+=1
  if self.count==num_decay_death_ticks then
   self:destroy(cas)
   return true
  end
 else
  self.pos=nil
 end
end

mutator=cellfind:new()

-- spawn a random neighbour cell
function mutator:mutate(ca)
 local offset=flr(rnd(#dirs))
 for i=1,4 do
  local dir=dirs[
   1+(i+offset)%#dirs
  ]
  local x=(
   self.pos.x+dir.dx+ca.specs.w
  )%ca.specs.w
  local y=(
   self.pos.y+dir.dy+ca.specs.h
  )%ca.specs.h
  if not ca:get(x,y) then
   ca:set(x,y)
   state.num_mutations+=bit0
   return
  end
 end
end

function mutator:update(cas)
 if rnd(1)<mutate_prob then
  self.do_mutate=true
 end
 if (not self.do_mutate) return

 cellfind.update(self,cas)

 if self.pos!=nil then
  self:mutate(
   cas[self.target_idx]
  )
  self.do_mutate=false
  self.pos=nil
 end
end

liveliness_check={}

function liveliness_check:new()
 local o=setmetatable({},self)
 self.__index=self

 o.min=9999
 o.level=liveliness_inc

 return o
end

function liveliness_check
 :update(num_cells)

 self.level*=liveliness_decay

 if num_cells<self.min then
  self.min=num_cells
  return
 end

 if num_cells>
    self.min+liveliness_limit
 then
  self.level+=liveliness_inc
  self.min+=liveliness_limit
  return true
 end
end

function revive(cas)
 local specs=cas[1].specs

 local a={}
 for ca in all(cas) do
  add(a,ca.bitgrid.a0+specs.bpr)
 end

 for row=1,specs.h do
  for col=0,specs.bpr-1,4 do
   local m=(
    $a[1]&$a[2]|$a[2]&$a[3]|
    $a[3]&$a[4]|$a[4]&$a[1]
   )
   for i=1,#cas do
    poke4(a[i],$a[i]|m)
    a[i]+=4
   end
  end
 end
end

-->8
tracks={
 {{10},{11},{12},{13}},
 {{14},{15,16},{17},{18,19}},
 {{20,21},{22},{23,24},{25,26}},
 {{27,28},{29},{30},{31}}
}
patterns={
 [0]=0x0.0080,
 [1]=0x0.8000
}

musicplayer={}

function musicplayer:new(history)
 local o=setmetatable({},self)
 self.__index=self

 o.history=history
 o.p_idx=1

 return o
end

function musicplayer:reset()
 --sync pattern index with music
 self.p_idx=stat(54)
 self:nxt_pattern()
end

function musicplayer:nxt_pattern()
 self.p_idx=(self.p_idx+1)%2
 local pat=patterns[self.p_idx]
 local nc=0

 for i=1,4 do
  local lvl=
   self.history:cell_level(i)
  if lvl>0 then
   local sl=tracks[i][lvl]
   local v=sl[
    self.p_idx%#sl+1
   ]&0x3f
   nc+=1
   pat|=v<<(nc*8-24)
  end
 end

 --disable empty channels
 for i=nc+1,4 do
  pat|=0x40<<(i*8-24)
 end

 poke4(0x3100+self.p_idx*4,pat)
end

function musicplayer:pattern_due()
 return (stat(50)>30 and
         stat(54)==self.p_idx)
end

function musicplayer:update()
 if self:pattern_due() then
  self:nxt_pattern()
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

function load_hiscores()
 if dget(0)!=cart_version then
  -- old (or no) cartdata
  dset(0,cart_version)
  if dget(0)==1 then
   --inserted auto-play hiscore
   --at index #2
   dset(3,dget(2))
   dset(2,0)
  else
   dset(1,0)
   dset(2,0)
   dset(3,0)
  end
 end

 state.hiscore={}
 state.hiscore[false]=dget(1)
 state.hiscore[true]=dget(2)
 state.loscore=dget(3)

 if state.loscore==0 then
  state.loscore=0x7fff.ffff
 end
end

function reset_garden()
 local specs=ca_specs:new(
  80,64,true
 )

 state.steps=0

 state.layers={}
 for i=1,4 do
  layer=ca:new(
   0x4400+i*16*64,specs
  )
  layer:randomize()
  layer.decay=decay:new(i)
  layer.mutator=mutator:new(i)
  layer.liveliness_check=
   liveliness_check:new()
  add(state.layers,layer)
 end
end

function start_game()
 state.t=0
 state.viewmode=5
 state.revive_wait=0
 state.num_revives=0
 state.num_decays=0
 state.num_mutations=0
 state.btnx_hold=0
 state.fadein=32
 state.target_wait=state.wait
 state.wait=5
 state.history:reset()
 state.music:reset()

 _draw=main_draw
 _update=main_update
end

function init_flowers()
 local flowers={}
 for i=1,14 do
  add(flowers,flower:new())
 end
 return flowers
end

function _init()
 cartdata("eriban_picogarden")

 state={}
 state.wait=0

 load_hiscores()

 expand=init_expand()
 state.flowers=init_flowers()

 state.history=cellhistory:new()
 state.music=musicplayer:new(
  state.history
 )

 pal(display_palette,1)

 --disable button repeat
 poke(0x5f5c,255)

 show_title()
 music(0)

 --show_label()
end

function draw_border()
 local d0=0x6000
 local a=d0+64*32
 for y=32,95 do
  memcpy(a,a+40,12)
  memcpy(a+52,a+12,12)
  a+=64
 end

 local a=d0
 local b=d0+64*96
 local d=64*64
 for y=0,31 do
  memcpy(a,a+d,64)
  memcpy(b,b-d,64)
  a+=64
  b+=64
 end
end

function draw_revive_rect()
 local x0=flr(24*(
  state.revive_wait/32
 ))-4
 local y0=state.revive_wait-4
 color(
  (32-state.revive_wait)*6<
  state.revive_delta and
  c_revive_hi or c_revive_lo
 )
 for w=1,3 do
  local y1=127-y0
  local x1=127-x0
  for x=max(x0,0),min(x1,127) do
   if (pget(x,y0)==0) pset(x,y0)
   if (pget(x,y1)==0) pset(x,y1)
  end
  for y=max(y0,0),min(y1,127) do
   if (pget(x0,y)==0) pset(x0,y)
   if (pget(x1,y)==0) pset(x1,y)
  end
  x0+=1
  y0+=1
 end
end

function draw_garden()
 for i,l in pairs(state.layers) do
  l:draw(i)
 end
end

function update_garden()
 local total_cells=0
 for i,layer in pairs(
  state.layers
 ) do
  local ncells=
   state.history:num_cells(i)
  if ncells>0 then
   layer:step()
   local chk=layer.liveliness_check
   local visible=(
    state.viewmode==i or
    state.viewmode%5==0
   )
   chk:update(ncells)
   if chk.level<decay_level then
    layer.decay:update(
     state.layers
    )
    layer.mutator:update(
     state.layers
    )
   end
  end
 end

 state.steps+=bit0
end

function main_draw()
 cls()

 local vm=state.viewmode

 if vm%5==0 then
  draw_garden()
 else
  state.layers[vm]:draw(vm)
 end
 draw_border()

 if state.revive_wait>0 then
  draw_revive_rect()
 end

 if vm==0 then
  state.history:draw_plot()
 elseif state.fadein>0 then
  rectfill(
   56-state.fadein,
   64-state.fadein,
   72+state.fadein,
   64+state.fadein,
   0
  )
 end

 if state.btnx_hold>0 then
  rectfill(34,61,95,67,0)
  color(c_txt)
  cprint("hold ❎ to exit",62)
 end
end

function switch_viewmode(delta)
 local skip_combined=(
  state.history:num_empty()
  ==#state.layers-1
 )
 local continue=true
 while continue do
  state.viewmode=(
   state.viewmode+delta+6
  )%6

  continue=(
   state.viewmode%5!=0
   and state.history:num_cells(
    state.viewmode
   )==0
  ) or (
   skip_combined and
   state.viewmode==5
  )
 end
end

function main_update()
 if btnp(⬆️) then
  if state.wait>0 then
   state.wait-=1
  end
 end
 if btnp(⬇️) then
  if state.wait<max_wait then
   state.wait+=1
  end
 end
 if btnp(⬅️) then
  switch_viewmode(-1)
 end
 if btnp(➡️) then
  switch_viewmode(1)
 end
 if btnp(🅾️) then
  if state.revive_wait==0 then
   local before=
    state.history:total_cells()
   revive(state.layers)
   state.revive_wait=min_revive_delay
   state.num_revives+=bit0
   state.revive_delta=(
    state.history:count()
    -before
   )
   return
  end
 end
 if btn(❎) then
  if state.fadein==0 then
   state.btnx_hold+=1
   if state.btnx_hold>=30 then
    gameover(true)
    return
   end
  end
 else
  state.btnx_hold=0
 end

 if state.fadein>0 then
  state.fadein-=1
 end

 state.t+=1
 if state.t%(1<<state.wait)!=0 then
  return
 end

 if state.wait!=
    state.target_wait and
    state.t%16==0
 then
  if state.wait<state.target_wait then
   state.wait+=1
  else
   state.wait-=1
  end
 end

 update_garden()
 state.music:update()

 if state.history:count()==0 then
  gameover()
 end

 if state.revive_wait>0 then
  state.revive_wait-=1
 end
end

function gameover(
 ignore_loscore
)
 local score=state.steps
 state.score=score

 reset_garden()

 local improved_lo=false
 if not ignore_loscore then
  if score<state.loscore then
   state.loscore=score
   dset(3,score)
   improved_lo=true
  end
 end

 local autoplay=(
  state.num_revives==0
 )
 local improved_hi=false
 if score>
    state.hiscore[autoplay]
 then
  state.hiscore[autoplay]=score
  dset(autoplay and 2 or 1,score)
  improved_hi=true
 end
 state.show_count=0

 state.show_loscore=(
  autoplay and
  state.loscore<
  state.hiscore[autoplay]
 )
 state.show_hiscore=(
  not autoplay
  or state.hiscore[autoplay]!=
     state.loscore
 )

 if improved_hi and
    state.show_hiscore
 then
  sfx(6)
 elseif improved_lo and
        state.show_loscore
 then
  sfx(7)
 else
  sfx(5)
 end

 _draw=gameover_draw
 _update=gameover_update
end

function gameover_draw()
 cls()
 draw_garden()
 draw_border()

 rectfill(23,32,103,95,0)

 spr(8,52,38,4,2)
 local x=0
 for i=1,2 do
  state.flowers[i]
  :draw(31+x*52,38)
  x+=1
 end

 color(c_txt)
 local y=59
 local autoplay=(
  state.num_revives==0
 )

 rprint("decays",66,y)
 rprint(
  u32_tostr(state.num_decays),
  98,y
 )
 y+=6

 rprint("mutations",66,y)
 rprint(
  u32_tostr(state.num_mutations),
  98,y
 )
 y+=6

 if not autoplay then
  rprint("revives",66,y)
  rprint(
   u32_tostr(state.num_revives),
   98,y
  )
  y+=6
 end

 rprint("score",66,y)
 rprint(
  u32_tostr(state.score),98,y
 )
 y+=10

 if state.show_loscore then
  color(
   state.loscore==state.score
   and c_hilo or c_txt
  )
  rprint("lo-score",66,y)
  rprint(
   u32_tostr(state.loscore),98,y
  )
  y+=6
 end
 if state.show_hiscore then
  color(
   state.hiscore[autoplay]==
    state.score
   and c_hilo or c_txt
  )
  rprint("hi-score",66,y)
  rprint(
   u32_tostr(
    state.hiscore[autoplay]
   ),98,y
  )
 end
end

function before_game_update(
 nflowers,autoplay_limit
)
 state.show_count+=1

 if state.show_count%30==0 then
  foreach(state.layers,ca.step)
  state.steps+=bit0
 end

 for i=1,nflowers do
  state.flowers[i]:update()
 end

 if ((
   state.show_count
    >=autoplay_limit and
   --ensure music updates right
   --away
   state.music:pattern_due()
  ) or
  state.show_count>45 and (
   btnp(❎) or btnp(🅾️)
  )
 ) then
  start_game()
 end
end

function gameover_update()
 before_game_update(2,300)
end

function show_title()
 reset_garden()

 state.show_count=0

 _draw=title_draw
 _update=title_update
end

function title_draw()
 cls()
 draw_garden()
 draw_border()

 rectfill(23,31,103,95,0)

 spr(3,46,51,5,2)
 color(2)
 cprint("by eriban",71)

 local x=0
 local y=0
 for i=1,14 do
  state.flowers[i]:draw(
   24+x*16,32+y*16
  )
  if x==4 then
   x=0
   y+=1
  elseif y%3==0 then
   x+=1
  else
   x=4
  end
 end
end

function title_update()
 before_game_update(14,600)
end

-->8
function show_label()
 _draw=label_draw
 _update=label_update
end

function label_update()
 foreach(
  state.flowers,
  flower.update
 )
end

function label_draw()
 --low-rez
 poke(0x5f2c,3)

 cls()

 local x=0
 local y=0
 for i=1,12 do
  state.flowers[i]:draw(
   x*16,y*16
  )
  if x==3 then
   x=0
   y+=1
  elseif y%3==0 then
   x+=1
  else
   x=3
  end
 end

 spr(3,14,20,5,2)

 color(2)
 print("by eriban",14,42)
end

__gfx__
00000000000000000000000000000004444004400444000444000000000000000444000040004444440004440000000000000000000000000000000000000000
00000000000000000000000000000004404404404404404404400000000000004400400404004404044044444000000000000000000000000000000000000000
007007000000e0000000000000000004404400004404404404400000000000004400000404004404044044000000000000000000000000000000000000000000
000770000000d0000000000000000004404404404400004404400000000000004404404444404404044044440000000000000000000000000000000000000000
000770000040f0c00000000000000004444004404404404404400000000000004404404404404404044044000000000000000000000000000000000000000000
00700700005090a00000000000000004400004404404404404400000000000004400404404404404044044444000000000000000000000000000000000000000
00000000002030b00000000000000004400004400444000444000000000000000444004404404404044004440000000000000000000000000000000000000000
00000000001060807000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000004440000400044440044440004440044440000000044400440440044400444400000000000000000000000000000000000000000
00000000000000000000000044004004040044044044044044444044444000000440440440440444440440440000000000000000000000000000000000000000
0000000012000e012400800044000004040044044044044044000044044000000440440440440440000440440000000000000000000000000000000000000000
00000000104003012050c00044044044444044440044044044440044044000000440440440440444400444400000000000000000000000000000000000000000
00000000024009010450b00044044044044044044044044044000044044000000440440040400440000440440000000000000000000000000000000000000000
0000000010050d002450a00044004044044044044044044044444044044000000440440040400444440440440000000000000000000000000000000000000000
00000000020506000000000004440044044044044044440004440044044000000044400004000044400440440000000000000000000000000000000000000000
0000000000450f012450700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000008c000e08cb00200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000080b00308c0a0500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000cb00d080ba0400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000800a0f00cba0100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000c0a06000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000ba0908cba0700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000700000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000070000000000000077700000000000000700000000
00000000000000000000000000000000000000000000000000000007000000000000007770000000000000777000000000000000000000000000000000000000
00000000000000000000000700000000000000777000000000000077700000000000070007000000000007070700000000000707070000000000070707000000
00000077700000000000007770000000000007000700000000000777770000000000070007000000000007000700000000000770770000000000077777000000
00000700070000000000077777000000000070000070000000007000007000000007700000770000000770000077000000077000007700000007707770770000
00007000007000000000770007700000000700070007000000077007007700000070000700007000007000070000700007007007007007000000770707700000
00007000007000000007770007770000000700707007000000777070707770000070007070007000077700707007770007070070700707007707777077770770
00007000007000000000770007700000000700070007000000077007007700000070000700007000007000070000700007007007007007000000770707700000
00000700070000000000077777000000000070000070000000007000007000000007700000770000000770000077000000077000007700000007707770770000
00000077700000000000007770000000000007000700000000000777770000000000070007000000000007000700000000000770770000000000077777000000
00000000000000000000000700000000000000777000000000000077700000000000070007000000000007070700000000000707070000000000070707000000
00000000000000000000000000000000000000000000000000000007000000000000007770000000000000777000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000070000000000000077700000000000000700000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000700000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000070000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000070700000000000007770000000000000707000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000707070000000000007770000000000000707000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000070000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00070000000700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00700000000070000077000000077000007700000007700000000000000000000000000000000000000000000000000000000000000000000000000000000000
00070000000700000077000000077000070070000070070000000000000000000000000000000000000000000000000000000000000000000000000000000000
00700000000070000077000000077000007700000007700000000000000000000000000000000000000000000000000000000000000000000000000000000000
00070000000700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000070000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000707070000000000007770000000000000707000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000070700000000000007770000000000000707000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000070000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__label__
00000000000000880000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000880000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000008800000000000000000000000000008888880000000000000000000000000000bb0000000000000000000000000000aaaaaa00000000000000
000000000000008800000000000000000000000000008888880000000000000000000000000000bb0000000000000000000000000000aaaaaa00000000000000
000000000000aaaaaa00000000000000000000000000bbbbbb00000000000000000000000000bb00bb0000000000000000000000000088888800000000000000
000000000000aaaaaa00000000000000000000000000bbbbbb00000000000000000000000000bb00bb0000000000000000000000000088888800000000000000
000000000088aaaaaa88000000000000000000000088bb88bb88000000000000000000000000bbaabb000000000000000000000000cc888888cc000000000000
000000000088aaaaaa88000000000000000000000088bb88bb88000000000000000000000000bbaabb000000000000000000000000cc888888cc000000000000
0000000000cc888888cc00000000000000000000008888008888000000000000000000000000aaaaaa000000000000000000000000aaaa00aaaa000000000000
0000000000cc888888cc00000000000000000000008888008888000000000000000000000000aaaaaa000000000000000000000000aaaa00aaaa000000000000
00000088cc0088888800cc8800000000000000888800000000008888000000000000000000aaaaaaaaaa000000000000000000ccaa0000000000aacc00000000
00000088cc0088888800cc8800000000000000888800000000008888000000000000000000aaaaaaaaaa000000000000000000ccaa0000000000aacc00000000
0000aaaa888800cc008888aaaa0000000088bbbb88000088000088bbbb8800000000bbbbaaaa000000aaaabbbb00000000aa8888aa0000aa0000aa8888aa0000
0000aaaa888800cc008888aaaa0000000088bbbb88000088000088bbbb8800000000bbbbaaaa000000aaaabbbb00000000aa8888aa0000aa0000aa8888aa0000
8888aaaa8888cc00cc8888aaaa8888000088bb880000880088000088bb88000000bb00aaaaaa000000aaaaaa00bb000000aa88880000aa00aa00008888aa0000
8888aaaa8888cc00cc8888aaaa8888000088bb880000880088000088bb88000000bb00aaaaaa000000aaaaaa00bb000000aa88880000aa00aa00008888aa0000
0000aaaa888800cc008888aaaa0000000088bbbb88000088000088bbbb8800000000bbbbaaaa000000aaaabbbb00000000aa8888aa0000aa0000aa8888aa0000
0000aaaa888800cc008888aaaa0000000088bbbb88000088000088bbbb8800000000bbbbaaaa000000aaaabbbb00000000aa8888aa0000aa0000aa8888aa0000
00000088cc0088888800cc8800000000000000888800000000008888000000000000000000aaaaaaaaaa000000000000000000ccaa0000000000aacc00000000
00000088cc0088888800cc8800000000000000888800000000008888000000000000000000aaaaaaaaaa000000000000000000ccaa0000000000aacc00000000
0000000000cc888888cc00000000000000000000008888008888000000000000000000000000aaaaaa000000000000000000000000aaaa00aaaa000000000000
0000000000cc888888cc00000000000000000000008888008888000000000000000000000000aaaaaa000000000000000000000000aaaa00aaaa000000000000
000000000088aaaaaa88000000000000000000000088bb88bb88000000000000000000000000bbaabb000000000000000000000000cc888888cc000000000000
000000000088aaaaaa88000000000000000000000088bb88bb88000000000000000000000000bbaabb000000000000000000000000cc888888cc000000000000
000000000000aaaaaa00000000000000000000000000bbbbbb00000000000000000000000000bb00bb0000000000000000000000000088888800000000000000
000000000000aaaaaa00000000000000000000000000bbbbbb00000000000000000000000000bb00bb0000000000000000000000000088888800000000000000
000000000000008800000000000000000000000000008888880000000000000000000000000000bb0000000000000000000000000000aaaaaa00000000000000
000000000000008800000000000000000000000000008888880000000000000000000000000000bb0000000000000000000000000000aaaaaa00000000000000
00000000000000880000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000880000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000880000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000880000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000bb88bb00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000cc0000000000000000
000000000000bb88bb00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000cc0000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000cc88cc00000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000cc88cc00000000000000
000000000088cccccc8800000000000000000000000000000000000000000000000000000000000000000000000000000000000000aa888888aa000000000000
000000000088cccccc8800000000000000000000000000000000000000000000000000000000000000000000000000000000000000aa888888aa000000000000
0000000000cc888888cc0000000000000000000000bbbbbbbb0000bbbb0000bbbbbb000000bbbbbb000000000000000000000000008888888888000000000000
0000000000cc888888cc0000000000000000000000bbbbbbbb0000bbbb0000bbbbbb000000bbbbbb000000000000000000000000008888888888000000000000
00000088cc0088888800cc88000000000000000000bbbb00bbbb00bbbb00bbbb00bbbb00bbbb00bbbb00000000000000000000aa88000000000088aa00000000
00000088cc0088888800cc88000000000000000000bbbb00bbbb00bbbb00bbbb00bbbb00bbbb00bbbb00000000000000000000aa88000000000088aa00000000
00bb00cc888800cc008888cc00bb00000000000000bbbb00bbbb00000000bbbb00bbbb00bbbb00bbbb000000000000000000cc888800008800008888cc000000
00bb00cc888800cc008888cc00bb00000000000000bbbb00bbbb00000000bbbb00bbbb00bbbb00bbbb000000000000000000cc888800008800008888cc000000
888800cc8888cc00cc8888cc008888000000000000bbbb00bbbb00bbbb00bbbb00000000bbbb00bbbb0000000000000000cc8888880088008800888888cc0000
888800cc8888cc00cc8888cc008888000000000000bbbb00bbbb00bbbb00bbbb00000000bbbb00bbbb0000000000000000cc8888880088008800888888cc0000
00bb00cc888800cc008888cc00bb00000000000000bbbbbbbb0000bbbb00bbbb00bbbb00bbbb00bbbb000000000000000000cc888800008800008888cc000000
00bb00cc888800cc008888cc00bb00000000000000bbbbbbbb0000bbbb00bbbb00bbbb00bbbb00bbbb000000000000000000cc888800008800008888cc000000
00000088cc0088888800cc88000000000000000000bbbb00000000bbbb00bbbb00bbbb00bbbb00bbbb00000000000000000000aa88000000000088aa00000000
00000088cc0088888800cc88000000000000000000bbbb00000000bbbb00bbbb00bbbb00bbbb00bbbb00000000000000000000aa88000000000088aa00000000
0000000000cc888888cc0000000000000000000000bbbb00000000bbbb0000bbbbbb000000bbbbbb000000000000000000000000008888888888000000000000
0000000000cc888888cc0000000000000000000000bbbb00000000bbbb0000bbbbbb000000bbbbbb000000000000000000000000008888888888000000000000
000000000088cccccc8800000000000000000000000000000000000000000000000000000000000000000000000000000000000000aa888888aa000000000000
000000000088cccccc8800000000000000000000000000000000000000000000000000000000000000000000000000000000000000aa888888aa000000000000
000000000000000000000000000000bbbbbb00000000bb000000bbbbbbbb0000bbbbbbbb000000bbbbbb0000bbbbbbbb000000000000cc88cc00000000000000
000000000000000000000000000000bbbbbb00000000bb000000bbbbbbbb0000bbbbbbbb000000bbbbbb0000bbbbbbbb000000000000cc88cc00000000000000
000000000000bb88bb0000000000bbbb0000bb0000bb00bb0000bbbb00bbbb00bbbb00bbbb00bbbbbbbbbb00bbbbbbbbbb000000000000cc0000000000000000
000000000000bb88bb0000000000bbbb0000bb0000bb00bb0000bbbb00bbbb00bbbb00bbbb00bbbbbbbbbb00bbbbbbbbbb000000000000cc0000000000000000
0000000000000088000000000000bbbb0000000000bb00bb0000bbbb00bbbb00bbbb00bbbb00bbbb00000000bbbb00bbbb000000000000000000000000000000
0000000000000088000000000000bbbb0000000000bb00bb0000bbbb00bbbb00bbbb00bbbb00bbbb00000000bbbb00bbbb000000000000000000000000000000
0000000000000000000000000000bbbb00bbbb00bbbbbbbbbb00bbbbbbbb0000bbbb00bbbb00bbbbbbbb0000bbbb00bbbb000000000000000000000000000000
0000000000000000000000000000bbbb00bbbb00bbbbbbbbbb00bbbbbbbb0000bbbb00bbbb00bbbbbbbb0000bbbb00bbbb000000000000000000000000000000
00000000000000aa000000000000bbbb00bbbb00bbbb00bbbb00bbbb00bbbb00bbbb00bbbb00bbbb00000000bbbb00bbbb000000000000bb0000000000000000
00000000000000aa000000000000bbbb00bbbb00bbbb00bbbb00bbbb00bbbb00bbbb00bbbb00bbbb00000000bbbb00bbbb000000000000bb0000000000000000
00000000000000aa000000000000bbbb0000bb00bbbb00bbbb00bbbb00bbbb00bbbb00bbbb00bbbbbbbbbb00bbbb00bbbb000000000000bb0000000000000000
00000000000000aa000000000000bbbb0000bb00bbbb00bbbb00bbbb00bbbb00bbbb00bbbb00bbbbbbbbbb00bbbb00bbbb000000000000bb0000000000000000
000000000000cccccc000000000000bbbbbb0000bbbb00bbbb00bbbb00bbbb00bbbbbbbb000000bbbbbb0000bbbb00bbbb0000000000aa00aa00000000000000
000000000000cccccc000000000000bbbbbb0000bbbb00bbbb00bbbb00bbbb00bbbbbbbb000000bbbbbb0000bbbb00bbbb0000000000aa00aa00000000000000
0000000000aaccaaccaa00000000000000000000000000000000000000000000000000000000000000000000000000000000000000aaccaaccaa000000000000
0000000000aaccaaccaa00000000000000000000000000000000000000000000000000000000000000000000000000000000000000aaccaaccaa000000000000
0000000000aabbbbbbaa00000000000000000000000000000000000000000000000000000000000000000000000000000000000000ccbbbbbbcc000000000000
0000000000aabbbbbbaa00000000000000000000000000000000000000000000000000000000000000000000000000000000000000ccbbbbbbcc000000000000
000000aaaabbaaaaaabbaaaa000000000000000000000000000000000000000000000000000000000000000000000000000000aacc00bbbbbb00ccaa00000000
000000aaaabbaaaaaabbaaaa000000000000000000000000000000000000000000000000000000000000000000000000000000aacc00bbbbbb00ccaa00000000
0000ccccbbaa00aa00aabbcccc00000000000000000000000000000000000000000000000000000000000000000000000000aaccbbbb00cc00bbbbccaa000000
0000ccccbbaa00aa00aabbcccc00000000000000000000000000000000000000000000000000000000000000000000000000aaccbbbb00cc00bbbbccaa000000
aaaaccaabbaaaa00aaaabbaaccaaaa000000000000000000000000000000000000000000000000000000000000000000bbbb00aabbbbcc00ccbbbbaa00bbbb00
aaaaccaabbaaaa00aaaabbaaccaaaa000000000000000000000000000000000000000000000000000000000000000000bbbb00aabbbbcc00ccbbbbaa00bbbb00
0000ccccbbaa00aa00aabbcccc00000000000000000000000000000000000000000000000000000000000000000000000000aaccbbbb00cc00bbbbccaa000000
0000ccccbbaa00aa00aabbcccc00000000000000000000000000000000000000000000000000000000000000000000000000aaccbbbb00cc00bbbbccaa000000
000000aaaabbaaaaaabbaaaa000000000000000000000000000000000000000000000000000000000000000000000000000000aacc00bbbbbb00ccaa00000000
000000aaaabbaaaaaabbaaaa000000000000000000000000000000000000000000000000000000000000000000000000000000aacc00bbbbbb00ccaa00000000
0000000000aabbbbbbaa00000000cccccc00cc00cc0000000000cccccc00cccccc00cccccc00cccccc00cccccc00cccc0000000000ccbbbbbbcc000000000000
0000000000aabbbbbbaa00000000cccccc00cc00cc0000000000cccccc00cccccc00cccccc00cccccc00cccccc00cccc0000000000ccbbbbbbcc000000000000
0000000000aaccaaccaa00000000cc00cc00cc00cc0000000000cc000000cc00cc0000cc0000cc00cc00cc00cc00cc00cc00000000aaccaaccaa000000000000
0000000000aaccaaccaa00000000cc00cc00cc00cc0000000000cc000000cc00cc0000cc0000cc00cc00cc00cc00cc00cc00000000aaccaaccaa000000000000
000000000000cccccc0000000000cccc0000cccccc0000000000cccc0000cccc000000cc0000cccc0000cccccc00cc00cc0000000000aa00aa00000000000000
000000000000cccccc0000000000cccc0000cccccc0000000000cccc0000cccc000000cc0000cccc0000cccccc00cc00cc0000000000aa00aa00000000000000
00000000000000aa000000000000cc00cc000000cc0000000000cc000000cc00cc0000cc0000cc00cc00cc00cc00cc00cc000000000000bb0000000000000000
00000000000000aa000000000000cc00cc000000cc0000000000cc000000cc00cc0000cc0000cc00cc00cc00cc00cc00cc000000000000bb0000000000000000
00000000000000aa000000000000cccccc00cccccc0000000000cccccc00cc00cc00cccccc00cccccc00cc00cc00cc00cc000000000000bb0000000000000000
00000000000000aa000000000000cccccc00cccccc0000000000cccccc00cc00cc00cccccc00cccccc00cc00cc00cc00cc000000000000bb0000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000cc000000000000000000000000000000cc000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000cc000000000000000000000000000000cc000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000cc000000000000000000000000000000cc000000000000000000000000000000aa0000000000000000
0000000000000000000000000000000000000000000000cc000000000000000000000000000000cc000000000000000000000000000000aa0000000000000000
0000000000000088000000000000000000000000000088bb88000000000000000000000000008888880000000000000000000000000088888800000000000000
0000000000000088000000000000000000000000000088bb88000000000000000000000000008888880000000000000000000000000088888800000000000000
00000000000088aa8800000000000000000000000088bb88bb8800000000000000000000008800aa00880000000000000000000000aa888888aa000000000000
00000000000088aa8800000000000000000000000088bb88bb8800000000000000000000008800aa00880000000000000000000000aa888888aa000000000000
000000000088aaaaaa880000000000000000000000cccccccccc000000000000000000000088aaaaaa880000000000000000000000aabbbbbbaa000000000000
000000000088aaaaaa880000000000000000000000cccccccccc000000000000000000000088aaaaaa880000000000000000000000aabbbbbbaa000000000000
0000000088aaaaaaaaaa88000000000000000088cc00cccccc00cc88000000000000008888aaaaaaaaaa888800000000000000aaaa0000000000aaaa00000000
0000000088aaaaaaaaaa88000000000000000088cc00cccccc00cc88000000000000008888aaaaaaaaaa888800000000000000aaaa0000000000aaaa00000000
00000088aaaa008800aaaa8800000000000088bbcccc00cc00ccccbb8800000000008800aaaa008800aaaa008800000000008888bb0000aa0000bb8888000000
00000088aaaa008800aaaa8800000000000088bbcccc00cc00ccccbb8800000000008800aaaa008800aaaa008800000000008888bb0000aa0000bb8888000000
000088aaaaaa880088aaaaaa88000000ccccbb88cccccc00cccccc88bbcccc00cccc88aaaaaa880088aaaaaa88cccc0000aa8888bb00aa00aa00bb8888aa0000
000088aaaaaa880088aaaaaa88000000ccccbb88cccccc00cccccc88bbcccc00cccc88aaaaaa880088aaaaaa88cccc0000aa8888bb00aa00aa00bb8888aa0000
00000088aaaa008800aaaa8800000000000088bbcccc00cc00ccccbb8800000000008800aaaa008800aaaa008800000000008888bb0000aa0000bb8888000000
00000088aaaa008800aaaa8800000000000088bbcccc00cc00ccccbb8800000000008800aaaa008800aaaa008800000000008888bb0000aa0000bb8888000000
0000000088aaaaaaaaaa88000000000000000088cc00cccccc00cc88000000000000008888aaaaaaaaaa888800000000000000aaaa0000000000aaaa00000000
0000000088aaaaaaaaaa88000000000000000088cc00cccccc00cc88000000000000008888aaaaaaaaaa888800000000000000aaaa0000000000aaaa00000000
000000000088aaaaaa880000000000000000000000cccccccccc000000000000000000000088aaaaaa880000000000000000000000aabbbbbbaa000000000000
000000000088aaaaaa880000000000000000000000cccccccccc000000000000000000000088aaaaaa880000000000000000000000aabbbbbbaa000000000000
00000000000088aa8800000000000000000000000088bb88bb8800000000000000000000008800aa00880000000000000000000000aa888888aa000000000000
00000000000088aa8800000000000000000000000088bb88bb8800000000000000000000008800aa00880000000000000000000000aa888888aa000000000000
0000000000000088000000000000000000000000000088bb88000000000000000000000000008888880000000000000000000000000088888800000000000000
0000000000000088000000000000000000000000000088bb88000000000000000000000000008888880000000000000000000000000088888800000000000000
0000000000000000000000000000000000000000000000cc000000000000000000000000000000cc000000000000000000000000000000aa0000000000000000
0000000000000000000000000000000000000000000000cc000000000000000000000000000000cc000000000000000000000000000000aa0000000000000000
0000000000000000000000000000000000000000000000cc000000000000000000000000000000cc000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000cc000000000000000000000000000000cc000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000

__sfx__
010100001806011060060600600000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
010100001406017060190601c06022060000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
010100001c06021060240602706028060000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
010100001d160211602316027160291602a1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
01010000197601d760227602576025760000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
01180800217601f7501c7401c7311c7211c7110010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
01181000217601f7501c7401c7311c7211c71100100000001d0302104024052240522404224032180000000009000000000000000000000000000000000000000900000000000000000000000000000000000000
01181000217601f7501c7401c7311c7211c71100100000001d0301c04018052180521804218032000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
911600000903300000000000000004620046100461500000000000000004615000000462004610046150000009043000000000000000046200461004615000000000000000046150000004620046100461500000
511600000904300000000000000004635000000904300000000000000000000000001063500000090330000009043000000000000000046350000009043000000000000000000000000010635000000903300000
111600000904300000000000402304635090230904300000000000000009033000001063509013090330000009043000000000004023046350902309043000000000000000090330000010635090130903300000
111600000904315615090330403304645090330904315625090331561509033156151064509023090330402309043156150903304033046450903309043156250903315615090331561510645090230903304023
911600000904009040090320902209012000020704007040070320702207012070120000000000000000000207040070400703207022070120000209040090400903209022090120901200002000000000000000
91160000050400504005032050220501200002020400204202032020220201200002000020000200002000020b0400b0420b0320b0220b012000020c0400c0420c0320c0220c0120000200002000020000200002
a91600000504005040050320502205012000020704007042070320702207012000020000200002000020000204040040420403204022040120000209040090420903209022090120000200002000020000200002
05160000090400000010030150300900015030070500704507000070300e03007030130300e030130300000007040000000e03007030000001303009040090450900009030100300903015030100301503000000
05160000050400c020050201103000000110200204000000000000202009020020200e0300902002020090200b020070200b0201303017000130200c0400700000020070100c020000100c030070100002007000
05160000050400c02005020110300000011020070400000000000070200e02007020130300e0200702000000040400b020040201003000000100200904000000000000902010020090100b0300c0200e02010020
a91600001c5401c5401c5401c5401c5321c5321c5321c5321c5321c5221c5221c5221c5121c5121a5401854017540175401753017532175221752215540155401554215532155321552215522155120000000000
a91600001c5401c5401c5401c5401c5421c5321c5321c5321c5221c5221c5221c5121c5121c5121a5401a5401c5401c5301c5321f5401f5401f53221540215402154221532215322152221522215120000000000
a91600002154021540215322153221522215121f5401f5401f5321f5321f5221f5121c5401c5421c5321c5221a5401a5401a5321a5321a5221a5121c5301c5301c5321c5221c5221c51200002000020000200002
191600001154015530115301c54000000115301a54000000000000000000000115301a5401853017530155301354017530135301a540000001353018540000000000000000000000000000000000000000000000
191600001154015530115301c54000000115301a5400000000000000001a530185201754018530175301552010540135301053017540000001053015540000000000000000000000000000000000000000000000
611600001c540005001a5401854017540185401754000500005001554013540155400050017540005000050017540005001554013540155401754010540005001c500005001a5001850017500185001750000500
611600001c540005001a5401854017540185401754000500005001554013540155400050017540005000050017540005001554013540155401854015540005000050000500005000050000500005000050000500
791600002474524715000002874528715000002674526715000000000000000000000000000000000000000026745267150000028745287150000024745247150000000000000000000000000000000000000000
79160000247452471500000287452871500000267452671500000000000000000000000000000000000000002874528715000002b7452b715000002d7452d7150000000000000000000000000000000000000000
7916000000000000000000028745287152b745267452671500000000000000000000000000000000000000000000000000000002674526715287452d7452d71500000000000000000000307452f7452d7452d715
79160000247452d7452d7152d70000000247452d7452d715267452f7452f7150000000000000000000000000267452f7452f7150000000000267452f7452f7152874530745307150000000000000000000000000
79160000247452d745247452d7452d7152d745267452f7452f7152f7452f715267452f745267452f7452f715267452f745267452f7452f7152f74528745307453071530745307152874530745307153074530715
__music__
01 0d12191f
02 0d131a1f
00 05424344
04 07424344
00 05424344
04 06424344
04 05424344

