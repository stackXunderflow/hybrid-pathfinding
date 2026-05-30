import type { Mesh, Point } from '@/types';

export function clonePoint(point: Point): Point {
	return { x: point.x, y: point.y };
}

export function polygonArea(points: Point[]): number {
	let area = 0;
	for (let i = 0; i < points.length; i++) {
		const a = points[i];
		const b = points[(i + 1) % points.length];
		area += a.x * b.y - b.x * a.y;
	}
	return area * 0.5;
}

export function ensureCcw(points: Point[]): Point[] {
	if (points.length < 3 || polygonArea(points) > 0) return points;
	return [...points].reverse();
}

export function translateMesh(mesh: Mesh, dx: number, dy: number) {
	for (const point of mesh.points) {
		point.x += dx;
		point.y += dy;
	}
}

export function distance(a: Point, b: Point): number {
	return Math.hypot(a.x - b.x, a.y - b.y);
}

export function distanceToSegment(point: Point, a: Point, b: Point): number {
	const vx = b.x - a.x;
	const vy = b.y - a.y;
	const wx = point.x - a.x;
	const wy = point.y - a.y;
	const len2 = vx * vx + vy * vy;
	if (len2 === 0) return distance(point, a);
	const t = Math.max(0, Math.min(1, (wx * vx + wy * vy) / len2));
	return Math.hypot(point.x - (a.x + vx * t), point.y - (a.y + vy * t));
}

export function pointInPolygon(point: Point, points: Point[]): boolean {
	let inside = false;
	for (let i = 0, j = points.length - 1; i < points.length; j = i++) {
		const a = points[i];
		const b = points[j];
		const intersects =
			a.y > point.y !== b.y > point.y &&
			point.x < ((b.x - a.x) * (point.y - a.y)) / (b.y - a.y) + a.x;
		if (intersects) inside = !inside;
	}
	return inside;
}

export function insertPointOnClosestEdge(mesh: Mesh, point: Point) {
	if (mesh.points.length < 2) {
		mesh.points.push(clonePoint(point));
		return;
	}

	let bestIndex = 0;
	let bestDistance = Infinity;
	for (let i = 0; i < mesh.points.length; i++) {
		const a = mesh.points[i];
		const b = mesh.points[(i + 1) % mesh.points.length];
		const d = distanceToSegment(point, a, b);
		if (d < bestDistance) {
			bestDistance = d;
			bestIndex = i + 1;
		}
	}

	mesh.points.splice(bestIndex, 0, clonePoint(point));
	mesh.points = ensureCcw(mesh.points);
}
