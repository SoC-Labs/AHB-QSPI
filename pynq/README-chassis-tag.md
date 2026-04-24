# Stamping a stable `board_tag` on each PYNQ-Z2 chassis

## Why

`fpgahub` names boards by USB-hub position (`hub_path`). When we
re-wire the rig — move a board to a different port on a StarTech
hub, swap chassis between benches, or rename interfaces — the
software label follows the cable, not the physical Zynq chassis.
That means "z2_01" in config.toml can end up pointing at a different
physical board than it did yesterday, without anything in the
software noticing.

Writing a `board_tag` into each Zynq's U-Boot QSPI env once, per
chassis, gives every physical board a stable identity that survives
reboots, SD reflashes, cable moves, and USB re-enumeration. The
`fpga-bringup` service reads this tag on every UART-recovery pass
and flags any chassis whose tag doesn't match the fpgahub name the
service is currently processing.

## When to run this ritual

- Once per physical Zynq chassis when you first bring it into the rig.
- Once after a QSPI wipe / FSBL reflash (the env lives in QSPI; it's
  cleared along with boot.bin when you reflash).

If a tag already exists, `fpga-bringup` will read it and never
overwrite — safe to re-run `fpga-bringup` at any time without
corrupting identities.

## The ritual

1. Get the chassis to the U-Boot `Zynq>` prompt. Options, easiest
   first:
   - Let it boot normally with a broken bootcmd — most of our rig
     lands at the prompt naturally because autoboot fails.
   - JTAG-reset it:
     `sudo /tmp/fpga-stage/pynq_z2.cfg`-based `openocd ... reset run`
     then immediately press a key on the TUL to interrupt autoboot.

2. Identify which physical chassis you're about to tag. The Zynq
   silicon has a fused PS-GEM MAC on *some* of our boards; read it
   off U-Boot's boot banner (`ethaddr=00:00:05:6b:02:c5`) or, if
   eFuse isn't programmed, pick any unique identifier that ties
   this session to this physical chassis (paint marker, serial
   sticker, board SKU). Write it down.

3. At `Zynq>`, stamp the board:

       Zynq> setenv board_tag z2_SN01
       Zynq> saveenv
       Zynq> reset

   Replace `z2_SN01` with whatever stable name you want
   (`[A-Za-z0-9_.-]+`, ≤ 31 chars, no spaces). Convention for the
   current rig: use the fpgahub name of the *_ps* board sitting in
   that chassis, e.g. `z2_01`. If you already know this chassis
   was the one the existing `pynq_z2_01_ps` config has been
   pointing at, name it `pynq_z2_01_ps`.

4. Confirm it took:

       Zynq> printenv board_tag
       board_tag=z2_SN01

5. Repeat per chassis.

## What happens next

Every time `fpga-bringup` touches a board's UART (i.e. during
recovery because a ping failed), it will:

- Read `board_tag` from U-Boot env.
- If absent — stamp it with the current fpgahub name, then saveenv.
  (The ritual above is only strictly necessary to *override* what
  `fpga-bringup` would auto-stamp.)
- If present and matches the current fpgahub name — log
  `board_tag=<name> (matches fpgahub name)`.
- If present and mismatches — log a WARN but never overwrites.
  The operator is the only thing that can change a tag once set.

Journal lines to look for:

```
fpga-bringup[*]:   board_tag absent; stamping 'pynq_z2_01_ps' (needs saveenv)
fpga-bringup[*]:   board_tag=pynq_z2_01_ps (matches fpgahub name)
fpga-bringup[*]:   WARN: board_tag=pynq_z2_03_ps but fpgahub is processing as
                        'pynq_z2_01_ps' — chassis may have been moved
```

The last one is the signal that yes, a physical board got moved
to a new hub_path and `config.toml` needs updating — or the
chassis_tag → hub_path lookup needs to be relied on instead of the
config.toml mapping (see upcoming Tier 3 in the board-stable-identity
plan).

## Troubleshooting

**Q: `setenv` prints `## Error: "board_tag" is in the env variable list but read-only`.**
A: Some Xilinx U-Boot builds declare `board_tag` read-only. Use a
different env var name like `chassis_tag` and update the regex in
`fpga-bringup`'s `_TAG_RE` to match (search for `board_tag` in
`/usr/local/sbin/fpga-bringup` on mapstone-dev).

**Q: `saveenv` prints `SF: ... Read only`.**
A: QSPI flash is either physically write-protected (jumper) or the
FSBL loaded a protection block. Unlikely on stock PYNQ-Z2 rootfs;
if it happens, reflash BOOT.BIN first.

**Q: TUL is silent even though I know Linux is running.**
A: Getty may have been disabled on the PS UART, or the kernel's
console has been redirected to something else. `xilinx@pynq` login
prompt should normally appear on `\r`. If it doesn't, probe via
JTAG (openocd `init; halt`) instead.
