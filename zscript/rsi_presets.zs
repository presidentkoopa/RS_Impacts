// RS_Impacts -- presets.
//
// A preset is a batch of CVar writes and nothing else, exactly as in
// RS_Darkness. It owns WHAT a hit looks like; it never touches rsi_enabled or
// the on_impact/on_death/on_damage switches, because those are what the player
// turns on and off and a preset stamping over them would read as the mod
// switching itself back on.

class RSI_Presets
{
	static void I(String n, int v)    { let c = CVar.FindCVar(n); if (c) c.SetInt(v); }
	static void F(String n, double v) { let c = CVar.FindCVar(n); if (c) c.SetFloat(v); }
	static void RGB(int r, int g, int b)
	{
		I("rsi_color_r", r); I("rsi_color_g", g); I("rsi_color_b", b);
	}

	// impact shape/tex/size/life. The four death parameters that used to follow
	// are gone with the death hook -- see rsi_handler.zs.
	static void Look(int ish, int itx, double isz, int ilf)
	{
		I("rsi_impact_shape", ish);
		I("rsi_impact_tex",   itx);
		F("rsi_impact_size",  isz);
		I("rsi_impact_life",  ilf);
	}

	static void Col(int mode, int r, int g, int b, double spread, double texStr, int every)
	{
		I("rsi_color_mode",   mode);
		RGB(r, g, b);
		F("rsi_color_spread", spread);
		F("rsi_tex_strength", texStr);
		I("rsi_impact_every", every);
	}

	static void Apply(int idx)
	{
		switch (idx)
		{
		default:
		case 0: Restrained();  break;
		case 1: Standard();    break;
		case 2: Arcade();      break;
		case 3: Sparks();      break;
		case 4: Bloom();       break;
		case 5: Grid();        break;
		case 6: Elemental();   break;
		case 7: Overload();    break;
		}
	}

	// Small, short, one shape. What you want if the stamps are meant to read as
	// feedback rather than as an effect.
	static void Restrained()
	{
		Look(3, 0, 40.0, 16);
		Col(0, 255, 128,  48,   0.0, 0.0, 5);
	}

	// The default. A ring on every third shot, a rolled burst on a death.
	static void Standard()
	{
		Look(3, 0, 64.0, 25);
		Col(2, 255, 128,  48,  90.0, 0.6, 3);
	}

	// Big, bright, every shot. Colour rolls hard.
	static void Arcade()
	{
		Look(9, 0, 96.0, 30);
		Col(1, 255,  64, 192, 360.0, 0.7, 1);
	}

	// Gouges along the shot direction, with sparks running down the wall.
	static void Sparks()
	{
		Look(2, 4, 80.0, 22);
		Col(3, 255, 176,  64,  40.0, 0.8, 2);
	}

	// Soft pools rather than structure. Reads as heat rather than as a diagram.
	static void Bloom()
	{
		Look(0, 1, 72.0, 30);
		Col(2, 255,  96,  32,  60.0, 0.9, 2);
	}

	// Hex and square tiling. The most obviously artificial of the set.
	static void Grid()
	{
		Look(4, 3, 88.0, 32);
		Col(1,  64, 208, 255, 140.0, 0.5, 3);
	}

	// Colour carries the damage type; shape stays constant so the colour is
	// the thing you read.
	static void Elemental()
	{
		Look(3, 0, 70.0, 26);
		Col(2, 255, 255, 255,   0.0, 0.5, 2);
	}

	// Everything on, every shot, damage flashes included.
	static void Overload()
	{
		Look(-1, -1, 110.0, 35);
		Col(1, 255, 255, 255, 360.0, 1.0, 1);
	}
}
