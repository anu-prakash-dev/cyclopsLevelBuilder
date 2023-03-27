# MIT License
#
# Copyright (c) 2023 Mark McKay
# https://github.com/blackears/cyclopsLevelBuilder
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# Godot uses clockwise winding, so all faces in this mesh sholud be clockwise as viewed from the outside

@tool
extends RefCounted
class_name ConvexMesh

enum Position { OVER, UNDER, CROSSING, ON }

#class VertexInfo extends RefCounted:
#	var point:Vector3
#	var uv:Vector2
#
#	func _init(point:Vector3):
#		self.point = point
#
#	func duplicate()->VertexInfo:
#		pass


class FaceInfo extends RefCounted:
	var vertices:PackedVector3Array = []
	var normal:Vector3
	var uv_transform:Transform2D = Transform2D.IDENTITY
	var material_index:int
	var face_index:int
	var selected:bool
	
	func append(vertex:Vector3):
		vertices.append(vertex)
	
	func init_from_points(points:Array[Vector3]):
		for p in points:
			vertices.append(p)
		normal = MathUtil.face_area_x2(vertices).normalized()
			
	func duplicate()->FaceInfo:
		var result:FaceInfo = FaceInfo.new()
		result.vertices = vertices
		result.normal = normal
		result.uv_transform = uv_transform
		result.material_index = material_index
		result.face_index = face_index
		result.selected = selected
		return result
			
	func plane_side_test(plane:Plane)->Position:
		var has_on:bool = false
		var has_over:bool = false
		var has_under:bool = false
		
		for v in vertices:
			if plane.has_point(v):
				has_on = true
			elif plane.is_point_over(v):
				has_over = true
			else:
				has_under = true
			
			if has_over and has_under:
				return Position.CROSSING
		
		if has_over:
			return Position.OVER
		if has_under:
			return Position.UNDER
		return Position.ON
	
	#Returns a new face equal to the portion of the face on the over side of the plane
	func cut_with_plane(plane:Plane)->FaceCutResult:
		var start_idx:int = 0
		
		for i in vertices.size():
			var v0:Vector3 = vertices[i]
			if plane.is_point_over(v0):
				start_idx = i
				break
		
		var bridge_vert0:Vector3
		var bridge_vert1:Vector3
		var new_verts:PackedVector3Array
		
		for i in vertices.size():
			var v0:Vector3 = vertices[wrap(i + start_idx, 0, vertices.size())]
			var v1:Vector3 = vertices[wrap(i + 1 + start_idx, 0, vertices.size())]
			
			var over0:bool = plane.is_point_over(v0)
			var over1:bool = plane.is_point_over(v1)
			
			if over0 and over1:
				new_verts.append(v0)
			elif !over0 and !over1:
				continue
			elif over0 and !over1:
				bridge_vert0 = plane.intersects_segment(v0, v1)
				new_verts.append(v0)
				new_verts.append(bridge_vert0)
			elif !over0 and over1:
				bridge_vert1 = plane.intersects_segment(v0, v1)
				new_verts.append(bridge_vert0)

		var new_face:FaceInfo = FaceInfo.new()
		new_face.vertices = new_verts
		new_face.normal = normal
		new_face.uv_transform = uv_transform
		new_face.material_index = material_index
		new_face.index = face_index
		new_face.selected = selected
			
		var result:FaceCutResult = FaceCutResult.new()
		result.face = new_face
		result.bridge_vert0 = bridge_vert0
		result.bridge_vert1 = bridge_vert1
		return result
				
class FaceCutResult extends RefCounted:
	var face:FaceInfo
	#Directed points of the cut edge added to face
	var bridge_vert0:Vector3
	var bridge_vert1:Vector3

var faces:Array[FaceInfo] = []
var bounds:AABB

func append_mesh(mesh:ImmediateMesh, material:Material, color:Color = Color.WHITE):
	
	for face in faces:
		mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, material)
#		print("face %s" % face.index)
		
		mesh.surface_set_normal(face.normal)
		
		for p in face.vertices:
			mesh.surface_set_color(color)
			
			var uv:Vector2
			var axis:MathUtil.Axis = MathUtil.get_longest_axis(face.normal)
			if axis == MathUtil.Axis.X:
				uv = Vector2(p.y, p.z)
			elif axis == MathUtil.Axis.Y:
				uv = Vector2(p.x, p.z)
			elif axis == MathUtil.Axis.Z:
				uv = Vector2(p.x, p.y)
				
			uv = face.uv_transform * uv
			mesh.surface_set_uv(uv)
			
			mesh.surface_add_vertex(p)
	
		mesh.surface_end()


func intersect_ray_closest(origin:Vector3, dir:Vector3)->IntersectResults:
	if bounds.intersects_ray(origin, dir) == null:
		return null
	
	var best_result:IntersectResults
	
	for face in faces:
		var tris:PackedVector3Array = MathUtil.trianglate_face(face.points, face.normal)
		for i in range(0, tris.size(), 3):
			var p0:Vector3 = tris[i]
			var p1:Vector3 = tris[i + 1]
			var p2:Vector3 = tris[i + 2]
			
			#Godot uses clockwise winding
			var tri_area_x2:Vector3 = MathUtil.triangle_area_x2(p0, p1, p2)
			
			var p_hit:Vector3 = MathUtil.intersect_plane(origin, dir, p0, tri_area_x2)
			if !p_hit.is_finite():
				continue
			
			if MathUtil.triangle_area_x2(p_hit, p0, p1).dot(tri_area_x2) < 0:
				continue
			if MathUtil.triangle_area_x2(p_hit, p1, p2).dot(tri_area_x2) < 0:
				continue
			if MathUtil.triangle_area_x2(p_hit, p2, p0).dot(tri_area_x2) < 0:
				continue
			
			#Intersection
			var dist_sq:float = (origin - p_hit).length_squared()
			if !best_result || best_result.distance_squared > dist_sq:
			
				var result:IntersectResults = IntersectResults.new()
				result.face_index = face.face_index
				result.normal = face.normal
				result.position = p_hit
				result.distance_squared = dist_sq
				
				best_result = result
					
	return best_result

#Keep volume on the over side of the plane
func cut_with_plane(plane:Plane, face_index:int, uv_transform:Transform2D = Transform2D.IDENTITY, material_index:int = 0, selected:bool = false)->ConvexMesh:
	var new_faces:Array[FaceInfo] = []
	
	var results:Array[FaceCutResult] = []
	
	for face in faces:
		var side:Position = face.plane_side_test(plane)
		if side == Position.OVER or side == Position.ON:
			new_faces.append(face.duplicate())
		elif side == Position.UNDER:
			continue
		else:
			var result:FaceCutResult = face.cut_with_plane(plane)
			results.append(result)
			new_faces.append(result.face)
	
	if new_faces.is_empty():
		#Cut eliminates everything
		return null
		
	if !results.is_empty():	
		var results_sorted:Array[FaceCutResult] = []
		results_sorted.append(results.pop_front())
		
		while !results.is_empty():
			for i in results.size():
				var r:FaceCutResult = results[i]
				if r.bridge_vert0.is_equal_approx(results_sorted.back().bridge_vert1):
					results_sorted.append(results.pop_at(i))
					break
				
		results_sorted.reverse()
		var face:FaceInfo = FaceInfo.new()
		for r in results_sorted:
			face.vertices.append(r.bridge_vert0)
		face.normal = MathUtil.face_area_x2(face.vertices).normalized()
		face.uv_transform = uv_transform
		face.material_index = material_index
		face.face_index = face_index
		face.selected = selected
		
		new_faces.append(face)
		#Build new face
	
	var mesh_result:ConvexMesh = ConvexMesh.new()
	mesh_result.faces = new_faces

	calc_bounds()
	
	return mesh_result

func calc_bounds():
	var all_verts:PackedVector3Array
	for f in faces:
		all_verts.append_array(f.vertices)
	bounds = MathUtil.get_bounds(all_verts)

func init_cube_huge():
	var min_float:float = -2^63
	var max_float:float = 2^63
	init_cube(Vector3(min_float, min_float, min_float), Vector3(max_float, max_float, max_float))

func init_cube(min_pos:Vector3, max_pos:Vector3):
	var p000:Vector3 = Vector3(min_pos.x, min_pos.y, min_pos.z)
	var p001:Vector3 = Vector3(min_pos.x, min_pos.y, max_pos.z)
	var p010:Vector3 = Vector3(min_pos.x, max_pos.y, min_pos.z)
	var p011:Vector3 = Vector3(min_pos.x, max_pos.y, max_pos.z)
	var p100:Vector3 = Vector3(max_pos.x, min_pos.y, min_pos.z)
	var p101:Vector3 = Vector3(max_pos.x, min_pos.y, max_pos.z)
	var p110:Vector3 = Vector3(max_pos.x, max_pos.y, min_pos.z)
	var p111:Vector3 = Vector3(max_pos.x, max_pos.y, max_pos.z)

	faces = []
	
	#In Godot, front faces wind clockwise
	var face:FaceInfo = FaceInfo.new()
	face.init_from_points([p000, p010, p011, p001])
	faces.append(face)

	face = FaceInfo.new()
	face.init_from_points([p001, p011, p111, p101])
	faces.append(face)

	face = FaceInfo.new()
	face.init_from_points([p101, p111, p110, p100])
	faces.append(face)
	
	face = FaceInfo.new()
	face.init_from_points([p100, p110, p010, p000])
	faces.append(face)
	
	face = FaceInfo.new()
	face.init_from_points([p000, p001, p101, p100])
	faces.append(face)
	
	face = FaceInfo.new()
	face.init_from_points([p011, p010, p110, p111])
	faces.append(face)
	
	calc_bounds()