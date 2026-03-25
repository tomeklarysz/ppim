import cv2
import os
import matplotlib.pyplot as plt

# 1. Load the provided video file
video_path = 'SynatSourceVideo003.mp4'  # Replace with your filename
cap = cv2.VideoCapture(video_path)

if not cap.isOpened():
    print("Error: Could not open video.")
else:
    # 3. Retrieve and print basic video properties
    width  = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    fps    = cap.get(cv2.CAP_PROP_FPS)
    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))

    print(f"Resolution: {width}x{height}")
    print(f"Total Frames: {total_frames}")
    print(f"FPS: {fps}")

    # 2. Display the first frame using matplotlib
    ret, first_frame = cap.read()
    if ret:
        # Convert BGR (OpenCV default) to RGB for Matplotlib
        plt.imshow(cv2.cvtColor(first_frame, cv2.COLOR_BGR2RGB))
        plt.title("First Frame")
        plt.axis('off')
        plt.show()

    # Define common parameters for tasks 4, 5, 6, 7
    fourcc = cv2.VideoWriter_fourcc(*'mp4v') # Default codec for mp4
    mjpeg_fourcc = cv2.VideoWriter_fourcc(*'MJPG') # MJPG codec
    
    # 4. Extract short segment (e.g., first 5 seconds)
    out_segment = cv2.VideoWriter('segment.mp4', fourcc, fps, (width, height))
    # 5. Grayscale segment
    out_gray = cv2.VideoWriter('segment_gray.mp4', fourcc, fps, (width, height), isColor=False)
    # 6. Resize (half resolution)
    out_resized = cv2.VideoWriter('resized.mp4', fourcc, fps, (width//2, height//2))
    # 7. Apply compression (MJPG as .avi)
    out_compressed = cv2.VideoWriter('compressed_mjpg.avi', mjpeg_fourcc, fps, (width, height))

    cap.set(cv2.CAP_PROP_POS_FRAMES, 0) # Reset to start
    for i in range(int(5 * fps)): # 5 second loop
        ret, frame = cap.read()
        if not ret: break
        
        # Task 4
        out_segment.write(frame)
        # Task 5
        gray_frame = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        out_gray.write(gray_frame)
        # Task 6
        resized_frame = cv2.resize(frame, (width//2, height//2))
        out_resized.write(resized_frame)
        # Task 7
        out_compressed.write(frame)

    # Release everything
    cap.release()
    out_segment.release()
    out_gray.release()
    out_resized.release()
    out_compressed.release()

    # 8. Compare file sizes
    def get_size(file): return os.path.getsize(file) / (1024 * 1024)
    
    print(f"\nFile Size Comparison:")
    print(f"Original: {get_size(video_path):.2f} MB")
    print(f"MJPG Compressed (.avi): {get_size('compressed_mjpg.avi'):.2f} MB")