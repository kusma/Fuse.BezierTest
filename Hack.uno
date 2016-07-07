using Fuse;
using Fuse.Controls;
using Fuse.Drawing;
using Uno;
using Uno.Collections;
using Uno.Graphics;

class Hack : Shape
{
	protected override void OnRooted()
	{
		base.OnRooted();
		UpdateManager.AddAction(OnUpdate);
	}

	protected override void OnUnrooted()
	{
		base.OnUnrooted();
		UpdateManager.RemoveAction(OnUpdate);
	}

	float2 P0, P1, P2;

	void OnUpdate()
	{
		double time = Uno.Diagnostics.Clock.GetSeconds();

		P0 = float2(300 + (float)Math.Sin(time * 2) * 50, 300 + (float)Math.Cos(time * 2) * 150);
		P1 = float2(600 + (float)Math.Sin(time) * 50,     600 + (float)Math.Cos(time) * 150);
		P2 = float2(900, 300);

		InvalidateVisual();
	}

	float2 NormalizeQuadraticBezier(float2 p0, float2 p1, float2 p2)
	{
		var u = p2 - p0;
		u = u / Vector.Dot(u, u);

		var v = float2(-u.Y, u.X);

		return float2(Vector.Dot(p1 - p0, u),
		              Vector.Dot(p1 - p0, v));
	}

	static float3 SolveCubic(float a, float b, float c)
	{
		var p  = b - a * a / 3,
		    p3 = p * p * p;
		var q = a * (2 * a * a - 9 * b) / 27 + c;
		var d = q * q + 4 * p3 / 27;
		var offset = -a / 3;

		if (d >= 0)
		{
			var z = Math.Sqrt(d);
			var x = (float2(z, -z) - q) / 2;
			var uv = Math.Sign(x) * Math.Pow(Math.Abs(x), float2(1.0f / 3));
			return float3(offset + uv.X + uv.Y);
		}

		var v = Math.Acos(-Math.Sqrt(-27 / p3) * q / 2) / 3;
		var m = Math.Cos(v),
		n = Math.Sin(v) * Math.Sqrt(3);
		return float3(m + m, -n - m, n - m) * Math.Sqrt(-p / 3) + offset;
	}

	static float DistanceNormalizedBezier(float2 p1, float2 p)
	{
		var b = float2(1, 0) - p1 * 2;
		var k = float3(3 * Vector.Dot(p1, b),
		               2 * Vector.Dot(p1, p1) + Vector.Dot(-p, b),
		                   Vector.Dot(-p, p1)) / Vector.Dot(b, b);
		var t = SolveCubic(k.X, k.Y, k.Z);
		t = Math.Clamp(t, 0, 1); // not needed if we don't care about the end-points

		var c = p1 * 2;
		var v = (c + b * t.X) * t.X - p;
		var d = Vector.Dot(v, v);
		v = (c + b * t.Y) * t.Y - p;
		d = Math.Min(d, Vector.Dot(v, v));
		v = (c + b * t.Z) * t.Z - p;
		return Math.Sqrt(Math.Min(d, Vector.Dot(v, v)));
	}

	protected override void DrawStroke(DrawContext dc, Stroke stroke)
	{
		var localToClipTransform = dc.GetLocalToClipTransform(this);

		float2 normalizedP0 = float2(0, 0);
		float2 normalizedP1 = NormalizeQuadraticBezier(P0, P1, P2);
		float2 normalizedP2 = float2(1, 0);

		float scale = Vector.Distance(P0, P2);
		float normalizedThickness = stroke.Width / scale;

		// TODO: generate better hull-geometry!
		var t0 = Vector.Normalize(P1 - P0);
		var t1 = Vector.Normalize(P1 - P2);

		var positions = new float2[] {
			P0 + float2(-t0.Y, t0.X) * stroke.Width,
			P1,
			P2 - float2(-t1.Y, t1.X) * stroke.Width,
		};

		var nt0 = Vector.Normalize(normalizedP1 - normalizedP0);
		var nt1 = Vector.Normalize(normalizedP1 - normalizedP2);
		var texCoords = new float2[] {
			normalizedP0 + float2(-nt0.Y, nt0.X) * normalizedThickness,
			normalizedP1,
			normalizedP2 - float2(-nt1.Y, nt1.X) * normalizedThickness
		};

		draw
		{
			apply Fuse.Drawing.Planar.PreMultipliedAlphaCompositing;
			CullFace : PolygonFace.None;

			float2 LocalVertex: vertex_attrib(positions);
			float2 TexCoord: vertex_attrib(texCoords);
			VertexCount: 3;

			ClipPosition: Vector.Transform(LocalVertex, localToClipTransform);

			float Distance: DistanceNormalizedBezier(normalizedP1, pixel TexCoord) * scale;
			float Coverage: Math.Clamp(stroke.Width - Distance, 0, 1);
			PixelColor: stroke.Color * Coverage;
		};
	}

	protected override void DrawFill(DrawContext dc, Brush fill)
	{
		var localToClipTransform = dc.GetLocalToClipTransform(this);

		var verts = new float2[] { P0, P1, P2 };
		draw
		{
			apply Fuse.Drawing.Planar.PreMultipliedAlphaCompositing;
			CullFace : PolygonFace.None;

			float2 LocalVertex: vertex_attrib(verts);
			float2 TexCoord: vertex_attrib(new float2[] { float2(0, 0), float2(0.5f, 0), float2(1, 1) });
			VertexCount: 3;

			ClipPosition: Vector.Transform(LocalVertex, localToClipTransform);

			float2 px: Math.Ddx(pixel TexCoord);
			float2 py: Math.Ddy(pixel TexCoord);
			float fx: (2 * TexCoord.X) * px.X - px.Y;
			float fy: (2 * TexCoord.Y) * py.X - py.Y;

			float Distance: (pixel TexCoord.X * TexCoord.X - TexCoord.Y) / Math.Sqrt(fx * fx + fy * fy);
			float Coverage: Math.Clamp(0.5f - Distance, 0, 1);
			PixelColor: float4(1, 0, 0, Coverage);
		};
	}
}
