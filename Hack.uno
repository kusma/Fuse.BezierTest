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

		var controlPointTemplate = FindTemplate("ControlPoint");
		if (controlPointTemplate != null)
		{
			_c0 = controlPointTemplate.New() as Visual;
			_c1 = controlPointTemplate.New() as Visual;
			_c2 = controlPointTemplate.New() as Visual;
			Children.Add(_c0);
			Children.Add(_c1);
			Children.Add(_c2);
		}
	}

	protected override void OnUnrooted()
	{
		base.OnUnrooted();
		UpdateManager.RemoveAction(OnUpdate);

		_c0 = null;
		_c1 = null;
		_c2 = null;
	}

	Visual _c0, _c1, _c2;
	float2 P0 { get { return _c0 != null ? Vector.Transform(_c0.LocalBounds.Center, _c0.WorldTransform).XY : float2(0, 0); } }
	float2 P1 { get { return _c1 != null ? Vector.Transform(_c1.LocalBounds.Center, _c1.WorldTransform).XY : float2(0.5f, 1); } }
	float2 P2 { get { return _c2 != null ? Vector.Transform(_c2.LocalBounds.Center, _c2.WorldTransform).XY : float2(1, 0); } }

	void OnUpdate()
	{
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
		return offset + float3(m + m, -n - m, n - m) * Math.Sqrt(-p / 3);
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

	float2 IntersectTangents(float2 p0, float2 t0, float2 p1, float2 t1)
	{
		float c1 = p0.X * t0.Y - p0.Y * t0.X;
		float c2 = p1.X * t1.Y - p1.Y * t1.X;
		float delta = t0.X * t1.Y - t0.Y * t1.X;
		return (t0 * c2 - t1 * c1) / delta;
	}

	protected override void DrawStroke(DrawContext dc, Stroke stroke)
	{
		var localToClipTransform = dc.GetLocalToClipTransform(this);

		float2 np0 = float2(0, 0);
		float2 np1 = NormalizeQuadraticBezier(P0, P1, P2);
		float2 np2 = float2(1, 0);

		float scale = Vector.Distance(P0, P2);
		float normalizedThickness = stroke.Width / scale;

		// TODO: generate better hull-geometry!
		var t0 = Vector.Normalize(P1 - P0);
		var t1 = Vector.Normalize(P1 - P2);
		var p0 = P0 + float2(-t0.Y, t0.X) * stroke.Width;
		var p2 = P2 - float2(-t1.Y, t1.X) * stroke.Width;
		var positions = new float2[]
		{
			p0,
			IntersectTangents(p0, t0, p2, t1),
			p2,
			P0 - float2(-t0.Y, t0.X) * stroke.Width,
			P2 + float2(-t1.Y, t1.X) * stroke.Width,
		};

		var nt0 = Vector.Normalize(np1 - np0);
		var nt1 = Vector.Normalize(np1 - np2);
		var nv0 = np0 + float2(-nt0.Y, nt0.X) * normalizedThickness;
		var nv2 = np2 - float2(-nt1.Y, nt1.X) * normalizedThickness;

		var texCoords = new float2[]
		{
			nv0,
			IntersectTangents(nv0, nt0, nv2, nt1),
			nv2,
			np0 - float2(-nt0.Y, nt0.X) * normalizedThickness,
			np2 + float2(-nt1.Y, nt1.X) * normalizedThickness,
		};

		draw
		{
			apply Fuse.Drawing.Planar.PreMultipliedAlphaCompositing;
			CullFace : PolygonFace.None;

			float2 LocalVertex: vertex_attrib(positions, Indices);
			float2 TexCoord: vertex_attrib(texCoords, Indices);
			ushort[] Indices : new ushort[] { 0,1,3, 1,4,3, 1,2,4 };
			VertexCount : 9;

			ClipPosition: Vector.Transform(LocalVertex, localToClipTransform);

			float Distance: DistanceNormalizedBezier(np1, pixel TexCoord) * scale;
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
