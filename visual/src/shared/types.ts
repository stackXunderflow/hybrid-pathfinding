export interface Point {
	x: number;
	y: number;
}

export interface Mesh {
	points: Point[];
}

export interface SceneInput {
	robot: Robot;
	borders: SceneBorders;
	meshs: Mesh[];
}

export interface SceneBorders {
	bottom_left: Point;
	top_right: Point;
}

export interface BlobContent {
	blob: Mesh;
	meshs: Mesh[];
}

export interface Robot {
	radius: number;
	start: Point;
	end: Point;
}

export interface SceneOutput {
	robot: Robot;
	borders: SceneBorders;
	blobs: BlobContent[];
	debug?: DebugLayout[] | null;
}

export interface BinaryRunResult {
	stdout: string;
	stderr: string;
	output: SceneOutput | null;
	error: string | null;
}

export interface DebugLayout {
	name: string;
	content: DebugItem[];
}

export type DebugItem =
	| DebugPoint
	| DebugMesh
	| DebugLine
	| DebugVector
	| DebugPath
	| DebugTriangulation
	| DebugGraph;

export interface DebugPoint {
	type: 'point';
	point: Point;
	label?: string;
}

export interface DebugMesh {
	type: 'mesh';
	points: Point[];
	label?: string;
	dashed?: boolean;
}

export interface DebugLine {
	type: 'line';
	from: Point;
	to: Point;
	label?: string;
}

export interface DebugVector {
	type: 'vector';
	origin: Point;
	vector: Point;
	label?: string;
}

export interface DebugPath {
	type: 'path';
	points: Point[];
	label?: string;
}

export interface DebugTriangulation {
	type: 'triangulation';
	points: Point[];
	triangles: number[];
	label?: string;
}

export interface DebugGraphEdge {
	from: number;
	to: number;
	weight: number;
}

export interface DebugGraph {
	type: 'graph';
	points: Point[];
	edges: DebugGraphEdge[];
	label?: string;
}
