// RS_Impacts -- the engine.
//
// Fires surface stamps: shapes of light painted onto whatever real surface a
// shot landed on. The drawing is the engine's (Level.SpawnSurfaceStamp ->
// func_surfacestamps.fp); everything here is the decision of WHEN and WITH
// WHAT, which is the only part a mod should own.
//
// Fire and forget. A stamp is published once and the engine ages it and drops
// it, so nothing here tracks a stamp after spawning it, nothing re-pushes per
// tic, and nothing has to be undone when the mod is switched off mid-bloom.
//
// WHY A TRACE.
//
// WorldHitscanFired gives the shot's origin, angle, pitch and distance -- not
// where it landed. A stamp needs the surface, so the landing point has to be
// found, and a line trace from the shooter along the same angle is exactly the
// query the engine already ran to resolve the shot. Puff-spotting was the
// alternative and it is worse: a puff is whatever class the weapon names, mods
// replace it constantly, and there is no reliable test for "this actor is a
// puff" that does not eventually guess wrong about somebody's mod.

class RSI_Handler : EventHandler
{
	const SHAPE_COUNT = 13;
	const TEX_COUNT   = 7;

	// The shapes worth rolling. Deliberately not 0..12: pool is a blob, invert
	// is a screen effect more than a shape, and bar and box are oriented, which
	// reads as arbitrary when nothing gave them a direction.
	static const int ShapeRoll[] = { 3, 4, 5, 6, 7, 8, 9, 10 };

	private int impactCounter;

	// ---- lifecycle ---------------------------------------------------------
	//
	// A PRESET APPLIES WHEN IT CHANGES, NOT ON EVERY MAP. The preset is a batch
	// of CVar writes; re-running it on each WorldLoaded wiped whatever the
	// player had tuned on the sliders since picking it, every level. The
	// last-applied index lives in a CVar (rsi_preset_applied) because this
	// handler is rebuilt per map and would otherwise forget.
	//
	// AND FROM THE MENU. The playsim is paused while the options menu is up,
	// so WorldTick never saw a preset change until the menu closed -- picking
	// one read as "does nothing". UiTick runs under the menu; CVar writes are
	// not scope-bound, so the same Apply works from there. Both sides fire
	// only on a change they have not seen, so applying twice is harmless.
	override void WorldTick()
	{
		SyncPreset();
	}
	override void UiTick()
	{
		SyncPreset();
	}
	clearscope static void SyncPreset()
	{
		int want = RSI_Util.GetI("rsi_preset", 1);
		if (want == RSI_Util.GetI("rsi_preset_applied", -1)) return;
		RSI_Presets.Apply(want);
		RSI_Presets.I("rsi_preset_applied", want);
	}
	override void WorldUnloaded(WorldEvent e)
	{
		if (Level) Level.ClearSurfaceStamps();
	}
	// ---- the three sources -------------------------------------------------

	// A hitscan was fired. THIS FORK'S EVENT CARRIES BOTH ENDS: AttackPos is
	// the real muzzle (the hand, in VR) and DamagePosition is where the shot
	// actually stopped -- the puff position. The old code re-traced from the
	// shooter ACTOR with the shot's angle, which in VR starts a body-width
	// away from the hand and lands somewhere near, not on, the hole.
	//
	// One short trace is still run, from the real muzzle to the real landing
	// point, because the event does not say WHAT was hit: a wall, a floor, the
	// sky, or a monster (no surface to paint). Actors are ignored and the
	// trace is capped just past the landing point, so a shot that stopped in
	// a monster finds nothing and a shot that stopped on a wall finds that
	// wall and nothing beyond it.
	override void WorldHitscanFired(WorldEvent e)
	{
		if (!Enabled() || !RSI_Util.GetB("rsi_on_impact", true)) return;
		if (!e || !e.Thing) return;

		// Throttle. A chaingun at every shot fills all sixteen slots in half a
		// second and every other source stops getting one.
		int every = max(1, RSI_Util.GetI("rsi_impact_every", 3));
		if (++impactCounter < every) return;
		impactCounter = 0;

		Vector3 from = e.AttackPos;
		Vector3 to   = e.DamagePosition;
		if (to == (0, 0, 0)) return;            // a clean miss leaves it unset
		Vector3 d = Level.Vec3Diff(from, to);
		double len = d.Length();
		if (len < 1.0) return;
		if (len > RSI_Util.GetF("rsi_trace_dist", 8192.0)) return;

		Sector sec = Level.PointInSector(from.xy);
		let lt = new("LineTracer");
		if (!lt.Trace(from, sec, d / len, len + 2.0, TRACE_HitSky,
			Line.ML_BLOCKHITSCAN | Line.ML_BLOCKEVERYTHING, true))
			return;
		if (!IsPaintable(lt.Results)) return;

		Stamp(lt.Results.HitPos, d / len,
			ShapeFor("rsi_impact_shape"),
			TexFor("rsi_impact_tex"),
			RSI_Util.GetF("rsi_impact_size", 64.0),
			RSI_Util.GetI("rsi_impact_life", 25),
			PickColor(e.DamageType, 0));
	}

	// DEATHS AND DAMAGE ARE NOT THIS MOD'S JOB.
	//
	// This used to hook WorldThingDied and WorldThingDamaged as well. It was
	// wrong by its own name: an impact is a shot landing on a SURFACE, and a
	// body dying in the middle of a room is not that. Deaths belong to
	// RS_DeathFX, which is a whole vocabulary of its own -- silhouettes,
	// tiers, the detector sweep -- and which would otherwise be fighting this
	// mod for the sixteen stamp slots on every single kill.

	// ---- decisions ---------------------------------------------------------

	bool Enabled()
	{
		return Level && RSI_Util.GetB("rsi_enabled", true);
	}

	// A stamp needs a real surface. Sky is not one: the shape lands on the
	// skybox and reads as a decal stuck to the horizon.
	bool IsPaintable(TraceResults r)
	{
		if (r.HitType == TRACE_HitNone)  return false;
		if (r.HitType == TRACE_HitActor) return false;
		if (r.HitType == TRACE_HasHitSky && RSI_Util.GetB("rsi_skip_sky", true)) return false;
		return true;
	}

	int ShapeFor(String cv)
	{
		int s = RSI_Util.GetI(cv, 3);
		if (s >= 0) return clamp(s, 0, SHAPE_COUNT - 1);
		return ShapeRoll[random(0, ShapeRoll.Size() - 1)];
	}

	int TexFor(String cv)
	{
		int t = RSI_Util.GetI(cv, 0);
		if (t >= 0) return clamp(t, 0, TEX_COUNT - 1);
		return random(1, TEX_COUNT - 1);
	}

	// 0 fixed, 1 random, 2 by damage type, 3 by how hard it hit.
	//
	// Every branch ends up going through RSI_Util.HSV rather than returning a
	// literal, so a rolled colour and a typed one sit in the same saturation
	// and value range and one never reads as washed out next to the other.
	Color PickColor(Name dmgType, int damage)
	{
		int mode = RSI_Util.GetI("rsi_color_mode", 2);
		Color base = RSI_Util.Fixed();

		if (mode == 0) return base;

		double h, s, v;
		RSI_Util.ToHSV(base, h, s, v);

		if (mode == 1)
		{
			double spread = clamp(RSI_Util.GetF("rsi_color_spread", 90.0), 0.0, 360.0);
			h = RSI_Util.WrapHue(h + frandom(-spread * 0.5, spread * 0.5));
			return RSI_Util.HSV(h, s, v);
		}

		if (mode == 2)
		{
			// Named types first, then anything unrecognised keeps the fixed
			// colour rather than being forced onto some arbitrary hue.
			if (dmgType == 'Fire')        return RSI_Util.HSV(22,  0.95, 1.0);
			if (dmgType == 'Ice')         return RSI_Util.HSV(195, 0.70, 1.0);
			if (dmgType == 'Electric')    return RSI_Util.HSV(210, 0.55, 1.0);
			if (dmgType == 'Poison')      return RSI_Util.HSV(95,  0.90, 0.9);
			if (dmgType == 'Slime')       return RSI_Util.HSV(85,  0.95, 0.85);
			if (dmgType == 'Drowning')    return RSI_Util.HSV(205, 0.60, 0.8);
			if (dmgType == 'Massacre')    return RSI_Util.HSV(0,   0.95, 1.0);
			if (dmgType == 'Disintegrate')return RSI_Util.HSV(280, 0.75, 1.0);
			return base;
		}

		// Harder hits run hotter: deep orange at a scratch, white-hot at 200.
		double f = clamp(damage / 200.0, 0.0, 1.0);
		return RSI_Util.HSV(RSI_Util.WrapHue(h + f * 40.0), s * (1.0 - f * 0.7), v);
	}

	// ---- the one call ------------------------------------------------------

	void Stamp(Vector3 at, Vector3 axis, int shape, int tex, double size, int life, Color col)
	{
		if (size <= 0 || life <= 0) return;
		Level.SpawnSurfaceStamp(shape, at, size, col, life, axis,
			tex, RSI_Util.GetF("rsi_tex_strength", 0.6));
	}
}

// ---- cvar shorthand --------------------------------------------------------
//
// clearscope throughout so the menu preview can reach the same helpers the
// handler does, the same way RS_GlowLanes and RS_Darkness do it.

class RSI_Util
{
	clearscope static double GetF(String name, double def = 0.0)
	{
		let c = CVar.FindCVar(name);
		return c ? c.GetFloat() : def;
	}

	clearscope static int GetI(String name, int def = 0)
	{
		let c = CVar.FindCVar(name);
		return c ? c.GetInt() : def;
	}

	clearscope static bool GetB(String name, bool def = false)
	{
		let c = CVar.FindCVar(name);
		return c ? c.GetBool() : def;
	}

	// Built from three int CVars, and ALWAYS with alpha 255. A colour that
	// loses its alpha is the most expensive bug in this family of mods -- the
	// glow lanes gate on `.a > 0` and silently draw nothing, with no error
	// anywhere -- so the alpha is written here once and never left to a caller.
	clearscope static Color Fixed()
	{
		return Color(255,
			clamp(GetI("rsi_color_r", 255), 0, 255),
			clamp(GetI("rsi_color_g", 128), 0, 255),
			clamp(GetI("rsi_color_b",  48), 0, 255));
	}

	clearscope static double WrapHue(double h)
	{
		while (h < 0.0)   h += 360.0;
		while (h >= 360.0) h -= 360.0;
		return h;
	}

	clearscope static Color HSV(double h, double s, double v)
	{
		h = WrapHue(h) / 60.0;
		int i = int(h);
		double f = h - i;
		double p = v * (1.0 - s);
		double q = v * (1.0 - s * f);
		double t = v * (1.0 - s * (1.0 - f));
		double r, g, b;
		if      (i == 0) { r = v; g = t; b = p; }
		else if (i == 1) { r = q; g = v; b = p; }
		else if (i == 2) { r = p; g = v; b = t; }
		else if (i == 3) { r = p; g = q; b = v; }
		else if (i == 4) { r = t; g = p; b = v; }
		else             { r = v; g = p; b = q; }
		return Color(255, int(r * 255), int(g * 255), int(b * 255));
	}

	clearscope static void ToHSV(Color c, out double h, out double s, out double v)
	{
		double r = c.r / 255.0, g = c.g / 255.0, b = c.b / 255.0;
		double mx = max(r, max(g, b));
		double mn = min(r, min(g, b));
		double d = mx - mn;
		v = mx;
		s = (mx <= 0.0) ? 0.0 : d / mx;
		if (d <= 0.0) { h = 0.0; return; }
		if      (mx == r) h = 60.0 * (((g - b) / d) % 6.0);
		else if (mx == g) h = 60.0 * (((b - r) / d) + 2.0);
		else              h = 60.0 * (((r - g) / d) + 4.0);
		h = WrapHue(h);
	}
}
