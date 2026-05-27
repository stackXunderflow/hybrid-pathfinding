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

export interface SceneOutput {
	blobs: BlobContent[];
}
