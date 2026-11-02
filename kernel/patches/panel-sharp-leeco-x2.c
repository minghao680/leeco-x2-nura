// SPDX-License-Identifier: GPL-2.0-only
/*
 * Sharp QHD dual-DSI command mode panel for the LeEco Le Max 2 (x2).
 *
 * The panel is driven over two bonded DSI links: DSI0 carries the left half
 * (720x2560) and DSI1 the right half, giving a combined 1440x2560 @60Hz
 * video-mode display.
 *
 * Panel parameters were taken from the vendor kernel devicetree:
 *   arch/arm/boot/dts/qcom/leeco/dsi-panel-sharp-dualmipi-cmd.dtsi
 *     h-front-porch = 120, h-back-porch = 64, h-pulse-width = 16
 *     v-back-porch  = 4,   v-front-porch = 8,  v-pulse-width = 4
 *     panel width 720, height 2560, framerate 60
 *
 * Structure is modelled on panel-sharp-lq079l1sx01.c, which is also a
 * two-link Sharp panel, and on panel-samsung-s6e3ha2.c whose 1440x2560
 * mode matches this panel exactly.
 *
 * NOTE: this driver is untested on hardware. The init sequence below is the
 * minimum needed to get a picture; vendor kernels use several extra
 * manufacturer commands (0xb0/0xb3/0xd6, see the dtsi above) which are
 * still missing.
 */

#include <linux/backlight.h>
#include <linux/delay.h>
#include <linux/gpio/consumer.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/of_graph.h>
#include <linux/regulator/consumer.h>

#include <drm/drm_connector.h>
#include <drm/drm_mipi_dsi.h>
#include <drm/drm_modes.h>
#include <drm/drm_panel.h>
#include <drm/drm_print.h>
#include <drm/drm_probe_helper.h>

#include <video/mipi_display.h>

struct leeco_x2_panel {
	struct drm_panel panel;
	struct mipi_dsi_device *dsi[2];

	struct gpio_desc *reset_gpio;
	struct regulator_bulk_data *supplies;
};

static const struct regulator_bulk_data leeco_x2_supplies[] = {
	{ .supply = "vddio" },
	{ .supply = "vdd" },
};

static inline struct leeco_x2_panel *to_leeco_x2_panel(struct drm_panel *panel)
{
	return container_of(panel, struct leeco_x2_panel, panel);
}

static void leeco_x2_panel_reset(struct leeco_x2_panel *ctx)
{
	/* vendor reset sequence: <1 10>, <0 10>, <1 10> (ms) */
	gpiod_set_value_cansleep(ctx->reset_gpio, 1);
	usleep_range(10000, 11000);
	gpiod_set_value_cansleep(ctx->reset_gpio, 0);
	usleep_range(10000, 11000);
	gpiod_set_value_cansleep(ctx->reset_gpio, 1);
	usleep_range(10000, 11000);
}

static int leeco_x2_panel_prepare(struct drm_panel *panel)
{
	struct leeco_x2_panel *ctx = to_leeco_x2_panel(panel);
	struct device *dev = panel->dev;
	struct mipi_dsi_device *dsi0 = ctx->dsi[0];
	struct mipi_dsi_device *dsi1 = ctx->dsi[1];
	struct mipi_dsi_multi_context dsi_ctx = { .dsi = NULL };
	int ret;

	ret = regulator_bulk_enable(ARRAY_SIZE(leeco_x2_supplies), ctx->supplies);
	if (ret) {
		dev_err(dev, "error enabling regulators (%d)\n", ret);
		return ret;
	}

	usleep_range(10000, 11000);

	if (ctx->reset_gpio)
		leeco_x2_panel_reset(ctx);

	usleep_range(10000, 11000);

	/* Soft reset, wait 10ms */
	mipi_dsi_dual_dcs_write_seq_multi(&dsi_ctx, dsi0, dsi1, MIPI_DCS_SOFT_RESET);
	mipi_dsi_msleep(&dsi_ctx, 10);

	/* vendor on-command sequence (dsi-panel-sharp-dualmipi-cmd.dtsi):
	 * MCAP page 0, then manufacturer interface settings, then the DCS
	 * standard block. Each vendor packet waits 10ms. */
	mipi_dsi_dual_dcs_write_seq_multi(&dsi_ctx, dsi0, dsi1, 0xb0, 0x00);
	mipi_dsi_msleep(&dsi_ctx, 10);
	mipi_dsi_dual_dcs_write_seq_multi(&dsi_ctx, dsi0, dsi1, 0xd6, 0x01);
	mipi_dsi_msleep(&dsi_ctx, 10);
	mipi_dsi_dual_dcs_write_seq_multi(&dsi_ctx, dsi0, dsi1, 0xb3, 0x10);
	mipi_dsi_msleep(&dsi_ctx, 10);

	/* write display brightness */
	mipi_dsi_dual_dcs_write_seq_multi(&dsi_ctx, dsi0, dsi1,
					  MIPI_DCS_SET_DISPLAY_BRIGHTNESS, 0xff);
	/* write control brightness */
	mipi_dsi_dual_dcs_write_seq_multi(&dsi_ctx, dsi0, dsi1,
					  MIPI_DCS_WRITE_CONTROL_DISPLAY, 0x0c);
	/* Set tear on */
	mipi_dsi_dual_dcs_write_seq_multi(&dsi_ctx, dsi0, dsi1,
					  MIPI_DCS_SET_TEAR_ON, 0x00);

	/* MCAP page 3 */
	mipi_dsi_dual_dcs_write_seq_multi(&dsi_ctx, dsi0, dsi1, 0xb0, 0x03);
	mipi_dsi_msleep(&dsi_ctx, 10);

	/* Set display on, wait 16ms */
	mipi_dsi_dual_dcs_write_seq_multi(&dsi_ctx, dsi0, dsi1, MIPI_DCS_SET_DISPLAY_ON);
	mipi_dsi_msleep(&dsi_ctx, 16);
	/* Sleep out, wait 120ms */
	mipi_dsi_dual_dcs_write_seq_multi(&dsi_ctx, dsi0, dsi1, MIPI_DCS_EXIT_SLEEP_MODE);
	mipi_dsi_msleep(&dsi_ctx, 120);

	if (dsi_ctx.accum_err)
		return dsi_ctx.accum_err;

	return 0;
}

static int leeco_x2_panel_unprepare(struct drm_panel *panel)
{
	struct leeco_x2_panel *ctx = to_leeco_x2_panel(panel);
	struct mipi_dsi_device *dsi0 = ctx->dsi[0];
	struct mipi_dsi_device *dsi1 = ctx->dsi[1];
	struct mipi_dsi_multi_context dsi_ctx = { .dsi = NULL };

	/* vendor off sequence: display off (50ms), sleep in (120ms) */
	mipi_dsi_dual_dcs_write_seq_multi(&dsi_ctx, dsi0, dsi1,
					  MIPI_DCS_SET_DISPLAY_OFF);
	mipi_dsi_msleep(&dsi_ctx, 50);
	mipi_dsi_dual_dcs_write_seq_multi(&dsi_ctx, dsi0, dsi1,
					  MIPI_DCS_ENTER_SLEEP_MODE);
	mipi_dsi_msleep(&dsi_ctx, 120);

	if (ctx->reset_gpio)
		gpiod_set_value_cansleep(ctx->reset_gpio, 1);

	return regulator_bulk_disable(ARRAY_SIZE(leeco_x2_supplies), ctx->supplies);
}

/*
 * Combined 1440x2560 @ 60Hz. The porches are the vendor values; each link
 * drives half the width, so hdisplay covers both halves here.
 */
#define LEECO_X2_HFP	120
#define LEECO_X2_HBP	64
#define LEECO_X2_HPW	16
#define LEECO_X2_VFP	8
#define LEECO_X2_VBP	4
#define LEECO_X2_VPW	4

static const struct drm_display_mode leeco_x2_default_mode = {
	.clock = (1440 + LEECO_X2_HFP + LEECO_X2_HBP + LEECO_X2_HPW) *
		 (2560 + LEECO_X2_VFP + LEECO_X2_VBP + LEECO_X2_VPW) * 60 / 1000,
	.hdisplay = 1440,
	.hsync_start = 1440 + LEECO_X2_HFP,
	.hsync_end = 1440 + LEECO_X2_HFP + LEECO_X2_HPW,
	.htotal = 1440 + LEECO_X2_HFP + LEECO_X2_HPW + LEECO_X2_HBP,
	.vdisplay = 2560,
	.vsync_start = 2560 + LEECO_X2_VFP,
	.vsync_end = 2560 + LEECO_X2_VFP + LEECO_X2_VPW,
	.vtotal = 2560 + LEECO_X2_VFP + LEECO_X2_VPW + LEECO_X2_VBP,
	.width_mm = 71,
	.height_mm = 126,
	.type = DRM_MODE_TYPE_DRIVER | DRM_MODE_TYPE_PREFERRED,
};

static int leeco_x2_panel_get_modes(struct drm_panel *panel,
				    struct drm_connector *connector)
{
	return drm_connector_helper_get_modes_fixed(connector,
						    &leeco_x2_default_mode);
}

static const struct drm_panel_funcs leeco_x2_panel_funcs = {
	.prepare = leeco_x2_panel_prepare,
	.unprepare = leeco_x2_panel_unprepare,
	.get_modes = leeco_x2_panel_get_modes,
};

static int leeco_x2_panel_probe(struct mipi_dsi_device *dsi)
{
	struct leeco_x2_panel *ctx;
	struct mipi_dsi_host *dsi_r_host;
	struct device *dev = &dsi->dev;
	struct device_node *dsi_r;
	struct mipi_dsi_device_info info = {
		.type = "leeco-x2-panel",
		.channel = 0,
		.node = NULL,
	};
	int ret;

	ctx = devm_kzalloc(dev, sizeof(*ctx), GFP_KERNEL);
	if (!ctx)
		return -ENOMEM;

	drm_panel_init(&ctx->panel, dev, &leeco_x2_panel_funcs,
		       DRM_MODE_CONNECTOR_DSI);

	ctx->supplies = devm_kcalloc(dev, ARRAY_SIZE(leeco_x2_supplies),
				     sizeof(*ctx->supplies), GFP_KERNEL);
	if (!ctx->supplies)
		return -ENOMEM;
	memcpy(ctx->supplies, leeco_x2_supplies, sizeof(leeco_x2_supplies));

	ret = devm_regulator_bulk_get(dev, ARRAY_SIZE(leeco_x2_supplies),
				      ctx->supplies);
	if (ret)
		return dev_err_probe(dev, ret, "failed to get supplies\n");

	ctx->reset_gpio = devm_gpiod_get_optional(dev, "reset", GPIOD_OUT_HIGH);
	if (IS_ERR(ctx->reset_gpio))
		return dev_err_probe(dev, PTR_ERR(ctx->reset_gpio),
				     "failed to get reset GPIO\n");

	/*
	 * The panel always sits on two DSI hosts: port 0 is DSI0, port 1 is
	 * DSI1. Look the second link up through the of-graph.
	 */
	dsi_r = of_graph_get_remote_node(dev->of_node, 1, -1);
	if (!dsi_r)
		return dev_err_probe(dev, -ENODEV,
				     "failed to find second DSI host node\n");

	dsi_r_host = of_find_mipi_dsi_host_by_node(dsi_r);
	of_node_put(dsi_r);
	if (!dsi_r_host)
		return dev_err_probe(dev, -EPROBE_DEFER,
				     "cannot get secondary DSI host\n");

	ctx->dsi[1] = devm_mipi_dsi_device_register_full(dev, dsi_r_host, &info);
	if (IS_ERR(ctx->dsi[1]))
		return dev_err_probe(dev, PTR_ERR(ctx->dsi[1]),
				     "second link registration failed\n");

	ctx->dsi[0] = dsi;
	mipi_dsi_set_drvdata(dsi, ctx);

	ret = drm_panel_of_backlight(&ctx->panel);
	if (ret)
		return dev_err_probe(dev, ret, "failed to get backlight\n");

	drm_panel_add(&ctx->panel);

	for (int i = 0; i < ARRAY_SIZE(ctx->dsi); i++) {
		if (!ctx->dsi[i])
			continue;

		ctx->dsi[i]->lanes = 4;
		ctx->dsi[i]->format = MIPI_DSI_FMT_RGB888;
		/* vendor: non_burst_sync_event, video mode without EOT */
		ctx->dsi[i]->mode_flags = MIPI_DSI_MODE_VIDEO |
					  MIPI_DSI_MODE_LPM |
					  MIPI_DSI_MODE_VIDEO_SYNC_PULSE;

		ret = devm_mipi_dsi_attach(dev, ctx->dsi[i]);
		if (ret < 0) {
			drm_panel_remove(&ctx->panel);
			return dev_err_probe(dev, ret,
					     "failed to attach to DSI%d\n", i);
		}
	}

	return 0;
}

static void leeco_x2_panel_remove(struct mipi_dsi_device *dsi)
{
	struct leeco_x2_panel *ctx = mipi_dsi_get_drvdata(dsi);

	drm_panel_remove(&ctx->panel);
}

static const struct of_device_id leeco_x2_of_match[] = {
	{ .compatible = "sharp,leeco-x2-panel" },
	{ }
};
MODULE_DEVICE_TABLE(of, leeco_x2_of_match);

static struct mipi_dsi_driver leeco_x2_panel_driver = {
	.driver = {
		.name = "panel-sharp-leeco-x2",
		.of_match_table = leeco_x2_of_match,
	},
	.probe = leeco_x2_panel_probe,
	.remove = leeco_x2_panel_remove,
};
module_mipi_dsi_driver(leeco_x2_panel_driver);

MODULE_AUTHOR("minghao680");
MODULE_DESCRIPTION("LeEco Le Max 2 (x2) Sharp QHD dual-DSI panel");
MODULE_LICENSE("GPL");
