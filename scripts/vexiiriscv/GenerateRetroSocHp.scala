package vexiiriscv

import spinal.core._
import spinal.lib.bus.misc.SizeMapping
import spinal.lib.bus.tilelink.M2sTransfers
import spinal.lib.system.tag.PmaRegionImpl
import vexiiriscv.misc.EmbeddedRiscvJtag

import java.nio.file.{Files, Paths}

/** Generates the fixed retroSoC RV32 Linux application core. */
object GenerateRetroSocHp extends App {
  require(args.length == 1, "usage: GenerateRetroSocHp <output-directory>")

  val output = Paths.get(args(0)).toAbsolutePath.normalize
  Files.createDirectories(output)

  val param = new ParamSimple()
  param.xlen = 32
  param.physicalWidth = 32
  param.resetVector = 0x38000000L
  param.asidWidth = 9
  param.addISA("m", "a", "f", "d", "c", "s", "u", "zicbom", "zicntr", "zihpm")
  param.fixIsaParams()

  param.decoders = 2
  param.lanes = 2
  param.withBtb = true
  param.withGShare = true
  param.withRas = true
  param.withLateAlu = true
  param.withAlignerBuffer = true
  param.withDispatcherBuffer = true
  param.allowBypassFrom = 0
  param.storeRs2Late = true
  param.divRadix = 4
  param.divArea = false

  param.fetchL1Enable = true
  param.fetchL1Sets = 64
  param.fetchL1Ways = 4
  param.fetchMemDataWidthMin = 64
  param.fetchL1RefillCount = 2
  param.fetchL1Prefetch = "nl"
  param.fetchBus = FetchBusEnum.axi4

  param.lsuL1Enable = true
  param.lsuL1Sets = 64
  param.lsuL1Ways = 4
  param.lsuMemDataWidthMin = 64
  param.lsuL1RefillCount = 8
  param.lsuL1WritebackCount = 8
  param.lsuStoreBufferSlots = 4
  param.lsuStoreBufferOps = 32
  param.lsuSoftwarePrefetch = true
  param.lsuHardwarePrefetch = "rpt"
  param.withLsuBypass = true
  param.lsuBus = LsuBusEnum.axi4
  param.lsuL1Bus = LsuL1BusEnum.axi4

  param.pmpParam.pmpSize = 16
  param.pmpParam.granularity = 4096
  param.additionalPerformanceCounters = 8
  param.privParam.withRdTime = true
  param.privParam.withDebug = true
  param.privParam.debugTriggers = 4
  param.embeddedJtagTap = true

  val config = SpinalConfig(
    targetDirectory = output.toString,
    inlineRom = true
  )
  config.generateVerilog {
    val plugins = param.plugins(hartId = 1)
    plugins.foreach {
      case plugin: EmbeddedRiscvJtag =>
        plugin.debugCd = ClockDomain.current.copy(
          reset = Bool().setName("EmbeddedRiscvJtag_logic_debug_reset")
        )
      case _ =>
    }
    ParamSimple.setPma(
      plugins,
      Seq(
        new PmaRegionImpl(
          mapping = SizeMapping(0x00000000L, 0x01000000L),
          isMain = false,
          isExecutable = true,
          transfers = M2sTransfers.all
        ),
        new PmaRegionImpl(
          mapping = SizeMapping(0x02000000L, 0x2E000000L),
          isMain = false,
          isExecutable = false,
          transfers = M2sTransfers.all
        ),
        new PmaRegionImpl(
          mapping = SizeMapping(0x30000000L, 0x00020000L),
          isMain = true,
          isExecutable = true,
          transfers = M2sTransfers.all
        ),
        new PmaRegionImpl(
          mapping = SizeMapping(0x38000000L, 0x04000000L),
          isMain = true,
          isExecutable = true,
          transfers = M2sTransfers.all
        ),
        new PmaRegionImpl(
          mapping = SizeMapping(0x40000000L, 0x02000000L),
          isMain = true,
          isExecutable = true,
          transfers = M2sTransfers.all
        ),
        new PmaRegionImpl(
          mapping = SizeMapping(0x48000000L, 0x08000000L),
          isMain = true,
          isExecutable = true,
          transfers = M2sTransfers.all
        )
      )
    )
    VexiiRiscv(plugins).setDefinitionName("vexii_riscv_hp_generated")
  }
}
