`timescale 1ns/1ps
module tb_Renderer;
    logic         clk;         
    logic         reset_n;       
    logic         iRead;         
    logic [31:0]  iAddress;      
    logic [7:0]   iBurstcount;    
    logic [31:0]  oData;          
    logic         oWaitrequest;  
    logic         oDatavalid;     
    logic         iWrite;         
    logic [31:0]  iWriteaddress;  
    logic [31:0]  iWritedata;    
	
	 integer face_count; // Số lượng face từ file .obj
    logic [31:0] base_address_diff_tex; // Địa chỉ texture diffuse
    logic [31:0] base_address_normal_tex; // Địa chỉ texture normal
    logic [31:0] base_address_specular_tex; // Địa chỉ texture specular
    integer diff_tex_size; // Kích thước texture diffuse (byte)
    integer normal_tex_size; // Kích thước texture normal (byte)
    integer specular_tex_size; // Kích thước texture specular (byte)
	 logic [31:0] base_address_z_buffer; // Địa chỉ Z-buffer
    integer z_buffer_size; // Kích thước Z-buffer (byte)
	 integer width_output = 1920;
	 integer height_output = 1080;

    RAM u_RAM (
        .clk(clk),
        .reset_n(reset_n),
        .iRead(iRead),
        .iAddress(iAddress),
        .iBurstcount(iBurstcount),
        .oData(oData),
        .oWaitrequest(oWaitrequest),
        .oDatavalid(oDatavalid),
        .iWrite(iWrite),
        .iWriteaddress(iWriteaddress),
        .iWritedata(iWritedata)
    );

    always #10 clk = ~clk;
    task write_vector(input [31:0] base_address, input [31:0] v[0:2], input int num_values);
        for (int i = 0; i < num_values; i++) begin
            @(posedge clk);
            iWrite = 1;
            iWriteaddress = base_address + (i * 4); 
            iWritedata = v[i];
            $display("Ghi vao RAM: dia chi=0x%h, gia tri=%.6f (hex=%h)", iWriteaddress, $bitstoshortreal(v[i]), v[i]);
            @(posedge clk);
            iWrite = 0; 
        end
    endtask

    task write_vectors(input [31:0] base_address);
        automatic logic [31:0] eye[0:2]    = {32'h3F800000, 32'h40000000, 32'h40400000}; // [1.0, 2.0, 3.0]
        automatic logic [31:0] center[0:2] = {32'h00000000, 32'h00000000, 32'h00000000}; // [0.0, 0.0, 0.0]
        automatic logic [31:0] up[0:2]     = {32'h00000000, 32'h3F800000, 32'h00000000}; // [0.0, 1.0, 0.0]
        automatic logic [31:0] light[0:2]  = {32'h40800000, 32'h40800000, 32'h40800000}; // [4.0, 4.0, 4.0]

        $display("Ghi vector eye vao RAM tai 0x%h", base_address);
        write_vector(base_address, eye, 3);
        $display("Ghi vector center vao RAM tai 0x%h", base_address + 12);
        write_vector(base_address + 12, center, 3);
        $display("Ghi vector up vao RAM tai 0x%h", base_address + 24);
        write_vector(base_address + 24, up, 3);
        $display("Ghi vector light vao RAM tai 0x%h", base_address + 36);
        write_vector(base_address + 36, light, 3);
    endtask

    task read_burst(input [31:0] base_address, input [7:0] burst_count, output [31:0] data[0:255]);
        @(posedge clk);
        iRead = 1;
        iAddress = base_address;
        iBurstcount = burst_count;
        @(posedge clk);
        iRead = 0;
        for (int i = 0; i < burst_count; i++) begin
            while (!oDatavalid) @(posedge clk); 
            data[i] = oData;
            $display("Doc du lieu[%0d] tu dia chi 0x%h: %.6f (hex=%h)", i, base_address + (i * 4), $bitstoshortreal(oData), oData);
            @(posedge clk);
        end
    endtask

    task read_obj_and_write_faces(input string filename, input [31:0] base_address);
        integer file, vertex_count, tex_count, norm_count;
        shortreal x, y, z, u, v, w;
        logic [31:0] vertices[0:2047][0:2]; 
        logic [31:0] tex_coords[0:2047][0:1]; 
        logic [31:0] normals[0:2047][0:2]; 
        integer v_idx[0:2], vt_idx[0:2], vn_idx[0:2]; 
        logic [31:0] temp_tex[0:2]; 
        string line;

        
        file = $fopen(filename, "r");
        if (file == 0) begin
            $display("Loi: Khong mo duoc file %s", filename);
            $finish;
        end

        vertex_count = 0;
        tex_count = 0;
        norm_count = 0;
        face_count = 0;

        
        while (!$feof(file)) begin
            if (!$fgets(line, file)) continue; 
            $display("Doc dong: %s", line); 
            if (line.substr(0,1) == "v ") begin
                if ($sscanf(line, "v %f %f %f", x, y, z) == 3) begin
                    vertices[vertex_count][0] = $shortrealtobits(x);
                    $display("vertices[%0d][0]: %.6f (hex=%h)", vertex_count, $bitstoshortreal(vertices[vertex_count][0]), vertices[vertex_count][0]);
                    vertices[vertex_count][1] = $shortrealtobits(y);
                    $display("vertices[%0d][1]: %.6f (hex=%h)", vertex_count, $bitstoshortreal(vertices[vertex_count][1]), vertices[vertex_count][1]);
                    vertices[vertex_count][2] = $shortrealtobits(z);
                    $display("vertices[%0d][2]: %.6f (hex=%h)", vertex_count, $bitstoshortreal(vertices[vertex_count][2]), vertices[vertex_count][2]);
                    vertex_count++;
                    $display("Doc vertex %0d: %.6f %.6f %.6f", vertex_count, x, y, z);
                end
            end
            else if (line.substr(0,2) == "vt ") begin
                if ($sscanf(line, "vt %f %f %f", u, v, w) == 3 || $sscanf(line, "vt %f %f", u, v) == 2) begin
                    tex_coords[tex_count][0] = $shortrealtobits(u);
                    $display("tex_coords[%0d][0]: %.6f (hex=%h)", tex_count, $bitstoshortreal(tex_coords[tex_count][0]), tex_coords[tex_count][0]);
                    tex_coords[tex_count][1] = $shortrealtobits(v);
                    $display("tex_coords[%0d][1]: %.6f (hex=%h)", tex_count, $bitstoshortreal(tex_coords[tex_count][1]), tex_coords[tex_count][1]);
                    tex_count++;
                    $display("Doc texture coord %0d: %.6f %.6f", tex_count, u, v);
                end
            end
            else if (line.substr(0,2) == "vn ") begin
                if ($sscanf(line, "vn %f %f %f", x, y, z) == 3) begin
                    normals[norm_count][0] = $shortrealtobits(x);
                    $display("normals[%0d][0]: %.6f (hex=%h)", norm_count, $bitstoshortreal(normals[norm_count][0]), normals[norm_count][0]);
                    normals[norm_count][1] = $shortrealtobits(y);
                    $display("normals[%0d][1]: %.6f (hex=%h)", norm_count, $bitstoshortreal(normals[norm_count][1]), normals[norm_count][1]);
                    normals[norm_count][2] = $shortrealtobits(z);
                    $display("normals[%0d][2]: %.6f (hex=%h)", norm_count, $bitstoshortreal(normals[norm_count][2]), normals[norm_count][2]);
                    norm_count++;
                    $display("Doc normal %0d: %.6f %.6f %.6f", norm_count, x, y, z);
                end
            end
            else if (line.substr(0,1) == "f ") begin
                $display("Gap dong face: %s", line); 
                if ($sscanf(line, "f %d/%d/%d %d/%d/%d %d/%d/%d",
                            v_idx[0], vt_idx[0], vn_idx[0],
                            v_idx[1], vt_idx[1], vn_idx[1],
                            v_idx[2], vt_idx[2], vn_idx[2]) == 9) begin
                    
                    for (int i = 0; i < 3; i++) begin
                        if (v_idx[i] > vertex_count || vt_idx[i] > tex_count || vn_idx[i] > norm_count) begin
                            $display("Loi: Chi so khong hop le: v=%0d (max %0d), vt=%0d (max %0d), vn=%0d (max %0d)",
                                     v_idx[i], vertex_count, vt_idx[i], tex_count, vn_idx[i], norm_count);
                            $finish;
                        end
                        if (v_idx[i] > 2048 || vt_idx[i] > 2048 || vn_idx[i] > 2048) begin
                            $display("Loi: Chi so vuot qua gioi han mang: v=%0d, vt=%0d, vn=%0d", v_idx[i], vt_idx[i], vn_idx[i]);
                            $finish;
                        end
                    end
                    $display("Doc face thanh cong: %0d/%0d/%0d %0d/%0d/%0d %0d/%0d/%0d",
                             v_idx[0], vt_idx[0], vn_idx[0],
                             v_idx[1], vt_idx[1], vn_idx[1],
                             v_idx[2], vt_idx[2], vn_idx[2]);

                    v_idx[0]--; vt_idx[0]--; vn_idx[0]--;
                    v_idx[1]--; vt_idx[1]--; vn_idx[1]--;
                    v_idx[2]--; vt_idx[2]--; vn_idx[2]--;

                    // Debug: In chi so sau khi tru
                    $display("Chi so sau khi tru 1: v_idx=[%0d,%0d,%0d], vt_idx=[%0d,%0d,%0d], vn_idx=[%0d,%0d,%0d]",
                             v_idx[0], v_idx[1], v_idx[2], vt_idx[0], vt_idx[1], vt_idx[2], vn_idx[0], vn_idx[1], vn_idx[2]);

                    // Ghi du lieu cho moi dinh cua face (8 gia tri moi dinh)
                    for (int i = 0; i < 3; i++) begin
                        // Ghi vertex (v, 3 gia tri, 12 byte)
                        $display("Ghi vertex %0d cua face %0d tai 0x%h gia tri (%.6f, %.6f, %.6f)",
                                 i, face_count, base_address + (face_count * 96) + (i * 32),
                                 $bitstoshortreal(vertices[v_idx[i]][0]),
                                 $bitstoshortreal(vertices[v_idx[i]][1]),
                                 $bitstoshortreal(vertices[v_idx[i]][2]));
                        write_vector(base_address + (face_count * 96) + (i * 32), vertices[v_idx[i]], 3);

                        // Ghi texture coord (vt, 2 gia tri, 8 byte)
                        temp_tex[0] = tex_coords[vt_idx[i]][0]; // u
                        temp_tex[1] = tex_coords[vt_idx[i]][1]; // v
                        temp_tex[2] = 32'h00000000; // Gia tri mac dinh (0.0)
                        $display("Ghi texture coord %0d cua face %0d tai 0x%h gia tri (%.6f, %.6f)",
                                 i, face_count, base_address + (face_count * 96) + (i * 32) + 12,
                                 $bitstoshortreal(temp_tex[0]), $bitstoshortreal(temp_tex[1]));
                        write_vector(base_address + (face_count * 96) + (i * 32) + 12, temp_tex, 2);

                        // Ghi normal (vn, 3 gia tri, 12 byte)
                        $display("Ghi normal %0d cua face %0d tai 0x%h gia tri (%.6f, %.6f, %.6f)",
                                 i, face_count, base_address + (face_count * 96) + (i * 32) + 20,
                                 $bitstoshortreal(normals[vn_idx[i]][0]),
                                 $bitstoshortreal(normals[vn_idx[i]][1]),
                                 $bitstoshortreal(normals[vn_idx[i]][2]));
                        write_vector(base_address + (face_count * 96) + (i * 32) + 20, normals[vn_idx[i]], 3);
                    end
                    face_count++;
                end
                else begin
                    $display("Loi: Khong doc duoc face tu dong: %s", line); // Debug: Bao loi
                end
            end
        end
        $fclose(file);
        $display("Da ghi %0d face vao RAM (tong %0d gia tri)", face_count, face_count * 24);
    endtask
	 
	 task read_tga_and_write_pixels(input string filename, input [31:0] base_address, output integer tex_size);
		 int file;
		 byte header[0:17];
		 int width, height, pixel_depth;
		 byte r, g, b;
		 int i;
		 logic [31:0] pixel_data;
		 int total_pixels;

		 $display("Mo file TGA: %s", filename);
		 file = $fopen(filename, "rb");
		 if (!file) begin
			  $display("Khong the mo file %s", filename);
			  tex_size = 0;
			  return;
		 end

		 for (i = 0; i < 18; i++) begin
			  header[i] = $fgetc(file);
		 end

		 width = {header[13], header[12]};
		 height = {header[15], header[14]};
		 pixel_depth = header[16];

		 $display("TGA: %0dx%0d, pixel depth = %0d", width, height, pixel_depth);
		 if (pixel_depth != 24) begin
			  $display("Chi ho tro TGA 24-bit RGB.");
			  $fclose(file);
			  tex_size = 0;
			  return;
		 end

		 total_pixels = width * height;
		 tex_size = total_pixels * 4; // Mỗi pixel 4 byte

		 for (i = 0; i < total_pixels; i++) begin
			  b = $fgetc(file);
			  g = $fgetc(file);
			  r = $fgetc(file);
			  pixel_data = {8'd0, r, g, b};

			  @(posedge clk);
			  iWrite = 1;
			  iWriteaddress = base_address + i * 4;
			  iWritedata = pixel_data;
			  $display("Pixel[%0d]: Addr=0x%h, R=%0h G=%0h B=%0h -> 0x%h", i, iWriteaddress, r, g, b, pixel_data);
			  @(posedge clk);
			  iWrite = 0;
		 end

		 $fclose(file);
		 $display("Da ghi texture %s: %0d pixel (%0d byte)", filename, total_pixels, tex_size);
	endtask

   task init_z_buffer(input [31:0] base_address);
		 integer total_pixels;
		 logic [31:0] max_depth;
		 total_pixels = width_output * height_output;
		 z_buffer_size = total_pixels * 4; // Mỗi giá trị Z là 4 byte
		 max_depth = 32'h3F800000; // 1.0 trong định dạng IEEE 754

		 $display("Khoi tao Z-buffer: %0dx%0d, kich thuoc %0d byte, tai 0x%h", width_output, height_output, z_buffer_size, base_address);
		 for (int i = 0; i < total_pixels; i++) begin
			  @(posedge clk);
			  iWrite = 1;
			  iWriteaddress = base_address + i * 4;
			  iWritedata = max_depth; // Ghi 1.0 cho tất cả pixel
			  $display("Z-buffer[%0d]: Addr=0x%h, Z=1.0", i, iWriteaddress);
			  @(posedge clk);
			  iWrite = 0;
		 end
   endtask

    initial begin
		 clk = 0;
		 reset_n = 0;
		 iRead = 0;
		 iAddress = 0;
		 iBurstcount = 0;
		 iWrite = 0;
		 iWriteaddress = 0;
		 iWritedata = 0;

		 // Reset
		 #20;
		 reset_n = 1;

		 // Ghi vector camera va anh sang vao RAM tai 0x0000
		 #20;
		 write_vectors(32'h0000);

		 // Đọc file OBJ và ghi dữ liệu face vao RAM tai 0x0030
		 #20;
		 $display("Đoc file OBJ va ghi du lieu vao RAM");
		 read_obj_and_write_faces("body.obj", 32'h0030);

		 // Tính địa chỉ bắt đầu cho texture diffuse
		 base_address_diff_tex = 32'h0030 + (face_count * 96);
		 $display("Địa chỉ texture diffuse: 0x%h", base_address_diff_tex);

		 // Đọc và ghi texture diffuse
		 #20;
		 $display("Đoc file diffuse texture va ghi du lieu vao RAM");
		 read_tga_and_write_pixels("body_diffuse.tga", base_address_diff_tex, diff_tex_size);

		 // Tính địa chỉ bắt đầu cho texture normal
		 base_address_normal_tex = base_address_diff_tex + diff_tex_size;
		 $display("Đia chi texture normal: 0x%h", base_address_normal_tex);

		 // Đọc và ghi texture normal
		 #20;
		 $display("Đoc file normal texture va ghi du lieu vao RAM");
		 read_tga_and_write_pixels("body_normal.tga", base_address_normal_tex, normal_tex_size);

		 // Tính địa chỉ bắt đầu cho texture specular
		 base_address_specular_tex = base_address_normal_tex + normal_tex_size;
		 $display("Đia chi texture specular: 0x%h", base_address_specular_tex);

		 // Đọc và ghi texture specular
		 #20;
		 $display("Đoc file specular texture va ghi du lieu vao RAM");
		 read_tga_and_write_pixels("body_specular.tga", base_address_specular_tex, specular_tex_size);
		 
		 // Tính địa chỉ Z-buffer
		 base_address_z_buffer = base_address_specular_tex + specular_tex_size;
		 $display("Đia chi Z-buffer: 0x%h", base_address_z_buffer);

		 #20;
		 $display("Khoi tao Z-buffer");
		 init_z_buffer(base_address_z_buffer);

		 #100;
		 $finish;
	end

endmodule