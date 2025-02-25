/*============================================================================
	FPGA implementation of Blockade by Gremlin Industries for MiSTer

	Author: Jim Gregory - https://github.com/JimmyStones/
	Version: 1.0
	Date: 2022-02-13

	This program is free software; you can redistribute it and/or modify it
	under the terms of the GNU General Public License as published by the Free
	Software Foundation; either version 3 of the License, or (at your option)
	any later version.

	This program is distributed in the hope that it will be useful,
	but WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
	GNU General Public License for more details.

	You should have received a copy of the GNU General Public License along
	with this program. If not, see <http://www.gnu.org/licenses/>.
===========================================================================*/

module emu
(
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,

	//Must be passed to hps_io module
	inout  [48:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        CLK_VIDEO,

	//Multiple resolutions are supported using different CE_PIXEL rates.
	//Must be based on CLK_VIDEO
	output        CE_PIXEL,

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	//if VIDEO_ARX[12] or VIDEO_ARY[12] is set then [11:0] contains scaled size instead of aspect ratio.
	output [12:0] VIDEO_ARX,
	output [12:0] VIDEO_ARY,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)
	output        VGA_F1,
	output [1:0]  VGA_SL,
	output        VGA_SCALER, // Force VGA scaler
	output        VGA_DISABLE, // analog out is off

	input  [11:0] HDMI_WIDTH,
	input  [11:0] HDMI_HEIGHT,
	output        HDMI_FREEZE,
	output        HDMI_BLACKOUT,

`ifdef MISTER_FB
	// Use framebuffer in DDRAM
	// FB_FORMAT:
	//    [2:0] : 011=8bpp(palette) 100=16bpp 101=24bpp 110=32bpp
	//    [3]   : 0=16bits 565 1=16bits 1555
	//    [4]   : 0=RGB  1=BGR (for 16/24/32 modes)
	//
	// FB_STRIDE either 0 (rounded to 256 bytes) or multiple of pixel size (in bytes)
	output        FB_EN,
	output  [4:0] FB_FORMAT,
	output [11:0] FB_WIDTH,
	output [11:0] FB_HEIGHT,
	output [31:0] FB_BASE,
	output [13:0] FB_STRIDE,
	input         FB_VBL,
	input         FB_LL,
	output        FB_FORCE_BLANK,

`ifdef MISTER_FB_PALETTE
	// Palette control for 8bit modes.
	// Ignored for other video modes.
	output        FB_PAL_CLK,
	output  [7:0] FB_PAL_ADDR,
	output [23:0] FB_PAL_DOUT,
	input  [23:0] FB_PAL_DIN,
	output        FB_PAL_WR,
`endif
`endif

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	// I/O board button press simulation (active high)
	// b[1]: user button
	// b[0]: osd button
	output  [1:0] BUTTONS,

	input         CLK_AUDIO, // 24.576 MHz
	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S,   // 1 - signed audio samples, 0 - unsigned
	output  [1:0] AUDIO_MIX, // 0 - no mix, 1 - 25%, 2 - 50%, 3 - 100% (mono)

	//ADC
	inout   [3:0] ADC_BUS,

	//SD-SPI
	output        SD_SCK,
	output        SD_MOSI,
	input         SD_MISO,
	output        SD_CS,
	input         SD_CD,

	//High latency DDR3 RAM interface
	//Use for non-critical time purposes
	output        DDRAM_CLK,
	input         DDRAM_BUSY,
	output  [7:0] DDRAM_BURSTCNT,
	output [28:0] DDRAM_ADDR,
	input  [63:0] DDRAM_DOUT,
	input         DDRAM_DOUT_READY,
	output        DDRAM_RD,
	output [63:0] DDRAM_DIN,
	output  [7:0] DDRAM_BE,
	output        DDRAM_WE,

	//SDRAM interface with lower latency
	output        SDRAM_CLK,
	output        SDRAM_CKE,
	output [12:0] SDRAM_A,
	output  [1:0] SDRAM_BA,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nCS,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nWE,

`ifdef MISTER_DUAL_SDRAM
	//Secondary SDRAM
	//Set all output SDRAM_* signals to Z ASAP if SDRAM2_EN is 0
	input         SDRAM2_EN,
	output        SDRAM2_CLK,
	output [12:0] SDRAM2_A,
	output  [1:0] SDRAM2_BA,
	inout  [15:0] SDRAM2_DQ,
	output        SDRAM2_nCS,
	output        SDRAM2_nCAS,
	output        SDRAM2_nRAS,
	output        SDRAM2_nWE,
`endif

	input         UART_CTS,
	output        UART_RTS,
	input         UART_RXD,
	output        UART_TXD,
	output        UART_DTR,
	input         UART_DSR,

	// Open-drain User port.
	// 0 - D+/RX
	// 1 - D-/TX
	// 2..6 - USR2..USR6
	// Set USER_OUT to 1 to read from USER_IN.
	input   [6:0] USER_IN,
	output  [6:0] USER_OUT,

	input         OSD_STATUS
);

///////// Default values for ports not used in this core /////////

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;
assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = '0;  

assign VGA_F1 = 0;
assign VGA_SCALER  = 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;

assign AUDIO_S = 1;
assign AUDIO_MIX = 0;

assign LED_DISK = 0;
assign LED_POWER = 0;
assign BUTTONS = 0;

//////////////////////////////////////////////////////////////////

wire [1:0] ar = status[9:8];

assign VIDEO_ARX = (!ar) ? 12'd8 : (ar - 1'd1);
assign VIDEO_ARY = (!ar) ? 12'd7 : 12'd0;

`include "build_id.v" 
localparam CONF_STR = {
	"A.BLOCKADE;;",
	"O35,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",  
	"O89,Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"OGJ,Analog Video H-Pos,0,-1,-2,-3,-4,-5,-6,-7,8,7,6,5,4,3,2,1;",
	"OKN,Analog Video V-Pos,0,-1,-2,-3,-4,-5,-6,-7,8,7,6,5,4,3,2,1;",
	"-;",
	"P1,Pause options;",
	"P1OP,Pause when OSD is open,On,Off;",
	"P1OQ,Dim video after 10s,On,Off;",
	"-;",
	"DIP;",
	"-;",
	"R0,Reset;",
	"J1,Fire,Start,Coin,Pause;",
	"Jn,A,Start,R,L;",
	"V,v",`BUILD_DATE
};

////////////////////   CLOCKS   ///////////////////

wire clk_sys;

pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_sys)
);

////////////////////   HPS   /////////////////////

wire [31:0] status;
wire  [1:0] buttons;
wire        forced_scandoubler;
wire        direct_video;
wire [21:0] gamma_bus;

wire        ioctl_download;
wire        ioctl_upload;
wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire  [7:0] ioctl_dout;
wire  [7:0] ioctl_index;

wire [15:0] joystick_0, joystick_1, joystick_2, joystick_3;

hps_io #(.CONF_STR(CONF_STR)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),

	.buttons(buttons),
	.status(status),
	.status_menumask({direct_video}),

	.forced_scandoubler(forced_scandoubler),
	.gamma_bus(gamma_bus),
	.direct_video(direct_video),

	.ioctl_download(ioctl_download),
	.ioctl_upload(ioctl_upload),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_index(ioctl_index),

	.joystick_0(joystick_0),
	.joystick_1(joystick_1),
	.joystick_2(joystick_2),
	.joystick_3(joystick_3)
);


///////////////////   CONTROLS   ////////////////////
wire p1_right = joystick_0[0];
wire p1_left = joystick_0[1];
wire p1_down = joystick_0[2];
wire p1_up = joystick_0[3];
wire p2_right = joystick_1[0];
wire p2_left = joystick_1[1];
wire p2_down = joystick_1[2];
wire p2_up = joystick_1[3];
wire p3_right = joystick_2[0];
wire p3_left = joystick_2[1];
wire p3_down = joystick_2[2];
wire p3_up = joystick_2[3];
wire p4_right = joystick_3[0];
wire p4_left = joystick_3[1];
wire p4_down = joystick_3[2];
wire p4_up = joystick_3[3];
wire btn_fire1 = joystick_0[4];
wire btn_fire2 = joystick_1[4];
wire btn_start = joystick_0[5] || joystick_1[5] || joystick_2[5] || joystick_3[5];
wire btn_start1 = joystick_0[5];
wire btn_start2 = joystick_1[5];
wire btn_coin = joystick_0[6] || joystick_1[6] || joystick_2[6] || joystick_3[6];
wire btn_pause = joystick_0[7] || joystick_1[7] || joystick_2[7] || joystick_3[7];

///////////////////   DIPS   ////////////////////

reg [2:0] dip_blockade_lives;
reg dip_comotion_lives;
reg [1:0] dip_hustle_coin;
reg [7:0] dip_hustle_freegame;
reg dip_hustle_time;
reg [1:0] dip_blasto_coin;
reg dip_blasto_demosounds;
reg dip_blasto_time;

reg dip_boom;
reg [1:0] dip_overlay_type;
reg [2:0] overlay_mask;

reg [7:0] sw[8];
always @(posedge clk_sys)
begin
	if (ioctl_wr && (ioctl_index==8'd254) && !ioctl_addr[24:3]) sw[ioctl_addr[2:0]] <= ioctl_dout;

 	case(game_mode)
	GAME_BLOCKADE:
	begin
		// The lives DIP behaves strangely in Blockade, so it is remapped here
		case(sw[0][1:0])
		2'd0: dip_blockade_lives <= 3'b011; // 3 lives
		2'd1: dip_blockade_lives <= 3'b110; // 4 lives
		2'd2: dip_blockade_lives <= 3'b100; // 5 lives
		2'd3: dip_blockade_lives <= 3'b000; // 6 lives
		endcase
		dip_overlay_type <= sw[0][3:2];
		dip_boom <= sw[0][4];
	end
	GAME_COMOTION:
	begin
		dip_comotion_lives <= sw[0][0];
		dip_overlay_type <= sw[0][2:1];
		dip_boom <= sw[0][3];
	end
	GAME_HUSTLE:
	begin
		dip_hustle_coin <= sw[0][1:0];
		case(sw[0][3:2])
		2'd0: dip_hustle_freegame <= 8'b11100001;
		2'd1: dip_hustle_freegame <= 8'b11010001;
		2'd2: dip_hustle_freegame <= 8'b10110001;
		2'd3: dip_hustle_freegame <= 8'b01110001;
		endcase
		dip_hustle_time <= sw[0][4];
		dip_overlay_type <= sw[0][6:5];
	end
	GAME_BLASTO:
	begin
		dip_blasto_coin = sw[0][1:0];
		dip_blasto_demosounds = sw[0][2];
		dip_blasto_time = sw[0][3];
		dip_overlay_type <= sw[0][5:4];
	end
	endcase

	// Generate overlay colour mask
	case(dip_overlay_type)
	2'd0: overlay_mask <= 3'b010; // Green
	2'd1: overlay_mask <= 3'b111; // White
	2'd2: overlay_mask <= 3'b011; // Yellow
	2'd3: overlay_mask <= 3'b001; // Red
	endcase

end

///////////////////   INPUTS   ////////////////////

reg [1:0] game_mode /*verilator public_flat*/;
localparam GAME_BLOCKADE = 0;
localparam GAME_COMOTION = 1;
localparam GAME_HUSTLE = 2;
localparam GAME_BLASTO = 3;
reg [7:0] IN_1;
reg [7:0] IN_2;
reg [7:0] IN_4;
always @(posedge clk_sys) 
begin
	// Set game mode
	if (ioctl_wr && (ioctl_index==8'd1)) game_mode <= ioctl_dout[1:0];

	// Game specific inputs
	case (game_mode)
		GAME_BLOCKADE: begin 	
			IN_1 <= ~{btn_coin, dip_blockade_lives, 1'b0, dip_boom, 2'b00};
			IN_2 <= ~{p1_left, p1_down, p1_right, p1_up, p2_left, p2_down, p2_right, p2_up};
			IN_4 <= ~{8'b00000000}; // Unused
		end
		GAME_COMOTION: begin 
			IN_1 <= ~{btn_coin, 2'b0, btn_start, dip_comotion_lives, dip_boom, 2'b00}; // Coin, Starts, DIPS
			IN_2 <= ~{p3_left, p3_down, p3_right, p3_up, p1_left, p1_down, p1_right, p1_up}; // P3 + P1 Controls
			IN_4 <= ~{p4_left, p4_down, p4_right, p4_up, p2_left, p2_down, p2_right, p2_up}; // P4 + P2 Controls
		end
		GAME_HUSTLE: begin 
			IN_1 <= ~{btn_coin, 2'b0, btn_start2, btn_start1, dip_hustle_time, dip_hustle_coin};
			IN_2 <= ~{p1_left, p1_down, p1_right, p1_up, p2_left, p2_down, p2_right, p2_up};
			IN_4 <= dip_hustle_freegame; // Extra DIPS
		end
		GAME_BLASTO: begin 
			IN_1 <= ~{btn_coin, 3'b0, dip_blasto_time, dip_blasto_demosounds, dip_blasto_coin};
			IN_2 <= ~{btn_fire1, btn_start2, btn_start1, 4'b0000, btn_fire2}; 
			IN_4 <= ~{p1_up, p1_left, p1_down, p1_right, p2_up, p2_left, p2_down, p2_right};
		end
	endcase
end

///////////////////   VIDEO   ////////////////////
reg ce_pix;
wire hblank, vblank, hs, vs, hs_original, vs_original;
wire video;
wire [2:0] video_rgb = {3{video}} & overlay_mask;
wire [5:0] rgb_out;

arcade_video #(256,24) arcade_video
(
	.*,
	.clk_video(clk_sys),
	.RGB_in({{4{rgb_out[5:4]}}, {4{rgb_out[3:2]}}, {4{rgb_out[1:0]}}}),
	.HBlank(hblank),
	.VBlank(vblank),
	.HSync(hs),
	.VSync(vs),
	.fx(status[5:3])
);

// H/V offset
wire [3:0]  voffset = status[23:20];
wire [3:0]  hoffset = status[19:16];
jtframe_resync jtframe_resync
(
	.clk(clk_sys),
	.pxl_cen(ce_pix),
	.hs_in(hs_original),
	.vs_in(vs_original),
	.LVBL(~vblank),
	.LHBL(~hblank),
	.hoffset(hoffset),
	.voffset(voffset),
	.hs_out(hs),
	.vs_out(vs)
);

///////////////////   PAUSE   ///////////////////
wire		pause_cpu;
pause #(2,2,2,24) pause (
	.*,
	.r({2{video_rgb[0]}}),
	.g({2{video_rgb[1]}}),
	.b({2{video_rgb[2]}}),
	.user_button(btn_pause),
	.pause_request(),
	.options(~status[26:25])
);

///////////////////   GAME   ////////////////////
reg rom_downloaded = 1'b0;
wire rom_download = ioctl_download && ioctl_index == 8'b0;
wire reset = (RESET | status[0] | buttons[1] | rom_download | ~rom_downloaded);
assign LED_USER = rom_download;
// Latch release reset if ROM data is received (stops sound circuit from going off if ROMs are not found)
always @(posedge clk_sys) if(rom_download && ioctl_dout > 8'b0) rom_downloaded <= 1'b1; 

blockade blockade (
	.clk(clk_sys),
	.reset(reset),
	.pause(pause_cpu),
	.game_mode(game_mode),
	.video(video),
	.ce_pix(ce_pix),
	.in_1(IN_1),
	.in_2(IN_2),
	.in_4(IN_4),
	.coin(btn_coin),
	.hsync(hs_original),
	.vsync(vs_original),
	.hblank(hblank),
	.vblank(vblank),
	.dn_addr(ioctl_addr[13:0]),
	.dn_data(ioctl_dout),
	.dn_wr(ioctl_wr & rom_download),
	.audio_l(AUDIO_L),
	.audio_r(AUDIO_R)
);

endmodule