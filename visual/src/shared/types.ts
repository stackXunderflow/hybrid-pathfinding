export interface Point {
	x: number;
	y: number;
}

export interface Mesh {
	points: Point[];
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
	blobs: BlobContent[];
}
