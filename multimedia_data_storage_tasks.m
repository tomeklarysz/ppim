clear;
clc;
close all;

% Paths relative to workspace root.
workspaceRoot = fileparts(fileparts(mfilename('fullpath')));
imageDir = fullfile(workspaceRoot, 'metadata', 'EXIF');
videoDir = fullfile(workspaceRoot, 'videoclips');
outputDir = fullfile(workspaceRoot, 'instructions-md', 'multimedia_results');
if ~exist(outputDir, 'dir')
    mkdir(outputDir);
end

fprintf('Workspace root: %s\n', workspaceRoot);
fprintf('Output dir: %s\n\n', outputDir);

%% Task 1 + 2: image set and format conversions
sourceImageName = 'alc_sin.jpg';
sourceImagePath = fullfile(imageDir, sourceImageName);
assert(exist(sourceImagePath, 'file') == 2, 'Source image not found: %s', sourceImagePath);

Iref = imread(sourceImagePath);
if size(Iref, 3) == 1
    Iref = repmat(Iref, [1 1 3]);
end

converted = {
    'jpg_q95', fullfile(outputDir, 'alc_sin_converted_q95.jpg');
    'jpg_q75', fullfile(outputDir, 'alc_sin_converted_q75.jpg');
    'jpg_q50', fullfile(outputDir, 'alc_sin_converted_q50.jpg');
    'png',  fullfile(outputDir, 'alc_sin_converted.png');
    'bmp',  fullfile(outputDir, 'alc_sin_converted.bmp');
    'tiff', fullfile(outputDir, 'alc_sin_converted.tiff')
};

imwrite(Iref, converted{1,2}, 'jpg', 'Quality', 95);
imwrite(Iref, converted{2,2}, 'jpg', 'Quality', 75);
imwrite(Iref, converted{3,2}, 'jpg', 'Quality', 50);
imwrite(Iref, converted{4,2}, 'png');
imwrite(Iref, converted{5,2}, 'bmp');
imwrite(Iref, converted{6,2}, 'tiff');

allImageFiles = [{sourceImagePath}; converted(:,2)];
allImageLabels = [{'jpg'}; converted(:,1)];

%% Task 3: pixel-by-pixel image comparison
imgMetrics = table('Size', [numel(allImageFiles)-1, 8], ...
    'VariableTypes', {'string','double','double','double','double','double','double','double'}, ...
    'VariableNames', {'ComparedFormat','FileSizeBytes','MSE_RGB','PSNR_dB','SSIM','MeanAbsDiffNorm','DifferentPixelRatio','DifferentPixelRatioPct'});

IrefD = im2double(Iref);
pixelDiffThreshold = 1/255;
for i = 2:numel(allImageFiles)
    Icmp = imread(allImageFiles{i});
    if size(Icmp, 3) == 1
        Icmp = repmat(Icmp, [1 1 3]);
    end
    Icmp = imresize(Icmp, [size(Iref,1), size(Iref,2)]);
    IcmpD = im2double(Icmp);

    mseVal = immse(IcmpD, IrefD);
    psnrVal = psnr(IcmpD, IrefD);
    ssimVal = ssim(IcmpD, IrefD);

    absDiff = abs(IcmpD - IrefD);
    meanAbsDiffNorm = mean(absDiff(:));

    diffMask = absDiff > pixelDiffThreshold;
    diffPixelRatio = nnz(any(diffMask,3)) / numel(diffMask(:,:,1));

    fileInfo = dir(allImageFiles{i});

    imgMetrics.ComparedFormat(i-1) = string(allImageLabels{i});
    imgMetrics.FileSizeBytes(i-1) = fileInfo.bytes;
    imgMetrics.MSE_RGB(i-1) = mseVal;
    imgMetrics.PSNR_dB(i-1) = psnrVal;
    imgMetrics.SSIM(i-1) = ssimVal;
    imgMetrics.MeanAbsDiffNorm(i-1) = meanAbsDiffNorm;
    imgMetrics.DifferentPixelRatio(i-1) = diffPixelRatio;
    imgMetrics.DifferentPixelRatioPct(i-1) = 100 * diffPixelRatio;
end

writetable(imgMetrics, fullfile(outputDir, 'image_metrics.csv'));

%% Task 4: video frame extraction and cross-format comparison
videoCandidates = {
    'The Blue Umbrella.mp4';
    'The Blue Umbrella.avi';
    'The Blue Umbrella.mov';
    'The Blue Umbrella.3gp'
};

videoPaths = cellfun(@(n) fullfile(videoDir, n), videoCandidates, 'UniformOutput', false);
existsMask = cellfun(@(p) exist(p, 'file') == 2, videoPaths);
videoPaths = videoPaths(existsMask);
videoNames = videoCandidates(existsMask);

assert(~isempty(videoPaths), 'No video files found.');

refIdx = find(endsWith(videoNames, '.mp4'), 1);
if isempty(refIdx)
    refIdx = 1;
end

refPath = videoPaths{refIdx};
refName = videoNames{refIdx};
refReader = VideoReader(refPath);

% Build a controlled lossy variant to avoid trivial all-zero video metrics
% when source files are merely container variants of the same stream.
derivedName = 'derived_lowq.avi';
derivedPath = fullfile(outputDir, derivedName);
fprintf('Creating derived lossy video for analysis: %s\n', derivedPath);
writer = VideoWriter(derivedPath, 'Motion JPEG AVI');
writer.Quality = 25;
writer.FrameRate = max(10, round(refReader.FrameRate / 2));
open(writer);
tmpReader = VideoReader(refPath);
while hasFrame(tmpReader)
    F = readFrame(tmpReader);
    smallF = imresize(F, 0.5, 'bilinear');
    writeVideo(writer, smallF);
end
close(writer);

videoPaths{end+1} = derivedPath;
videoNames{end+1} = derivedName;

sampleFrameCount = 60;
timeStep = min(refReader.Duration, 30) / sampleFrameCount;
sampleTimes = (0:sampleFrameCount-1) * timeStep;
sampleTimes = sampleTimes(sampleTimes < refReader.Duration);

videoMetrics = table('Size', [numel(videoPaths), 15], ...
    'VariableTypes', {'string','double','double','double','double','double','double','double','double','double','double','double','double','double','double'}, ...
    'VariableNames', {'VideoFile','FileSizeBytes','FramesCompared','MSE_RGB_Avg','PSNR_dB_Avg','SSIM_Avg','MeanAbsDiffNorm_Avg','DifferentPixelRatio_Avg','DifferentPixelRatioPct_Avg','DurationSec','FrameRate','FileSizeDiffPct_vsRef','DurationDiffMs_vsRef','FrameRateDiffPct_vsRef','TemporalStructureDiff_vsRef'});

refFileInfo = dir(refPath);
refDuration = refReader.Duration;
refFrameRate = refReader.FrameRate;

% Build a temporal signature for the reference video: average frame-to-frame
% change over uniformly sampled timestamps.
refTemporal = [];
prevRef = [];
for k = 1:numel(sampleTimes)
    t = sampleTimes(k);
    refReader.CurrentTime = t;
    try
        F = readFrame(refReader);
    catch
        continue;
    end
    if size(F, 3) == 1
        F = repmat(F, [1 1 3]);
    end
    FD = im2double(F);
    if ~isempty(prevRef)
        refTemporal(end+1,1) = mean(abs(FD(:) - prevRef(:))); %#ok<SAGROW>
    end
    prevRef = FD;
end

for i = 1:numel(videoPaths)
    vPath = videoPaths{i};
    vName = videoNames{i};

    try
        vReader = VideoReader(vPath);
    catch ME
        warning('Skipping %s (cannot open codec): %s', vName, ME.message);
        continue;
    end

    fileInfo = dir(vPath);

    if strcmp(vPath, refPath)
        videoMetrics.VideoFile(i) = string(vName);
        videoMetrics.FileSizeBytes(i) = fileInfo.bytes;
        videoMetrics.FramesCompared(i) = numel(sampleTimes);
        videoMetrics.MSE_RGB_Avg(i) = 0;
        videoMetrics.PSNR_dB_Avg(i) = 100;
        videoMetrics.SSIM_Avg(i) = 1;
        videoMetrics.MeanAbsDiffNorm_Avg(i) = 0;
        videoMetrics.DifferentPixelRatio_Avg(i) = 0;
        videoMetrics.DifferentPixelRatioPct_Avg(i) = 0;
        videoMetrics.DurationSec(i) = vReader.Duration;
        videoMetrics.FrameRate(i) = vReader.FrameRate;
        videoMetrics.FileSizeDiffPct_vsRef(i) = 0;
        videoMetrics.DurationDiffMs_vsRef(i) = 0;
        videoMetrics.FrameRateDiffPct_vsRef(i) = 0;
        videoMetrics.TemporalStructureDiff_vsRef(i) = 0;
        continue;
    end

    mseVals = [];
    psnrVals = [];
    ssimVals = [];
    madVals = [];
    dprVals = [];
    temporalVals = [];
    prevCmp = [];

    for k = 1:numel(sampleTimes)
        t = sampleTimes(k);
        if t >= vReader.Duration || t >= refReader.Duration
            continue;
        end

        refReader.CurrentTime = t;
        vReader.CurrentTime = t;

        try
            Fref = readFrame(refReader);
            Fcmp = readFrame(vReader);
        catch
            continue;
        end

        if size(Fref, 3) == 1
            Fref = repmat(Fref, [1 1 3]);
        end
        if size(Fcmp, 3) == 1
            Fcmp = repmat(Fcmp, [1 1 3]);
        end

        Fcmp = imresize(Fcmp, [size(Fref,1), size(Fref,2)]);

        FrefD = im2double(Fref);
        FcmpD = im2double(Fcmp);

        mseValFrame = immse(FcmpD, FrefD);
        mseVals(end+1,1) = mseValFrame;
        if mseValFrame == 0
            psnrVals(end+1,1) = 100;
        else
            psnrVals(end+1,1) = psnr(FcmpD, FrefD);
        end
        ssimVals(end+1,1) = ssim(FcmpD, FrefD);

        absDiff = abs(FcmpD - FrefD);
        madVals(end+1,1) = mean(absDiff(:));
        dprVals(end+1,1) = nnz(any(absDiff > pixelDiffThreshold,3)) / numel(absDiff(:,:,1));

        if ~isempty(prevCmp)
            temporalVals(end+1,1) = mean(abs(FcmpD(:) - prevCmp(:))); %#ok<SAGROW>
        end
        prevCmp = FcmpD;
    end

    videoMetrics.VideoFile(i) = string(vName);
    videoMetrics.FileSizeBytes(i) = fileInfo.bytes;
    videoMetrics.FramesCompared(i) = numel(mseVals);
    videoMetrics.MSE_RGB_Avg(i) = mean(mseVals, 'omitnan');
    videoMetrics.PSNR_dB_Avg(i) = mean(psnrVals, 'omitnan');
    videoMetrics.SSIM_Avg(i) = mean(ssimVals, 'omitnan');
    videoMetrics.MeanAbsDiffNorm_Avg(i) = mean(madVals, 'omitnan');
    videoMetrics.DifferentPixelRatio_Avg(i) = mean(dprVals, 'omitnan');
    videoMetrics.DifferentPixelRatioPct_Avg(i) = 100 * mean(dprVals, 'omitnan');
    videoMetrics.DurationSec(i) = vReader.Duration;
    videoMetrics.FrameRate(i) = vReader.FrameRate;
    videoMetrics.FileSizeDiffPct_vsRef(i) = 100 * abs(fileInfo.bytes - refFileInfo.bytes) / refFileInfo.bytes;
    videoMetrics.DurationDiffMs_vsRef(i) = 1000 * abs(vReader.Duration - refDuration);
    videoMetrics.FrameRateDiffPct_vsRef(i) = 100 * abs(vReader.FrameRate - refFrameRate) / refFrameRate;

    nTemporal = min(numel(refTemporal), numel(temporalVals));
    if nTemporal > 0
        videoMetrics.TemporalStructureDiff_vsRef(i) = mean(abs(refTemporal(1:nTemporal) - temporalVals(1:nTemporal)), 'omitnan');
    else
        videoMetrics.TemporalStructureDiff_vsRef(i) = NaN;
    end
end

videoMetrics = videoMetrics(videoMetrics.VideoFile ~= "", :);
writetable(videoMetrics, fullfile(outputDir, 'video_metrics.csv'));

%% Task 5: average difference ratios and plots
imgAvgDiffRatio = mean(imgMetrics.DifferentPixelRatio, 'omitnan');
vidAvgDiffRatio = mean(videoMetrics.DifferentPixelRatio_Avg, 'omitnan');

% Structural ratio is useful when frame-wise pixel metrics are exactly equal
% (e.g., files differ by container/timing metadata but decode identically).
videoStructPerFile = ((videoMetrics.FileSizeDiffPct_vsRef / 100) + ...
    (abs(videoMetrics.DurationDiffMs_vsRef) / max(1e-9, 1000 * refDuration)) + ...
    (videoMetrics.FrameRateDiffPct_vsRef / 100)) / 3;
vidAvgStructRatio = mean(videoStructPerFile, 'omitnan');

summary = table(imgAvgDiffRatio, 100*imgAvgDiffRatio, vidAvgDiffRatio, 100*vidAvgDiffRatio, ...
    vidAvgStructRatio, 100*vidAvgStructRatio, ...
    'VariableNames', {'ImageAvgDiffRatio','ImageAvgDiffRatioPct','VideoAvgDiffRatio','VideoAvgDiffRatioPct','VideoAvgStructureRatio','VideoAvgStructureRatioPct'});

writetable(summary, fullfile(outputDir, 'summary_diff_ratio.csv'));

fprintf('\n=== IMAGE METRICS ===\n');
disp(imgMetrics);

fprintf('\n=== VIDEO METRICS ===\n');
disp(videoMetrics);

fprintf('\nNote: derived_lowq.avi is intentionally generated for non-trivial quality differences.\n');

fprintf('\n=== SUMMARY ===\n');
disp(summary);

f1 = figure('Name', 'Image File Size Comparison');
bar(categorical(imgMetrics.ComparedFormat), imgMetrics.FileSizeBytes);
ylabel('Bytes');
title('Image File Sizes by Encoded Format');
grid on;
saveas(f1, fullfile(outputDir, 'plot_image_sizes.png'));

f2 = figure('Name', 'Image Difference Ratio');
bar(categorical(imgMetrics.ComparedFormat), imgMetrics.DifferentPixelRatioPct);
ylabel('Different Pixel Ratio [%]');
title('Image Pixel Difference vs Source JPG');
grid on;
saveas(f2, fullfile(outputDir, 'plot_image_diff_ratio.png'));

f3 = figure('Name', 'Video File Size Comparison');
bar(categorical(videoMetrics.VideoFile), videoMetrics.FileSizeBytes);
ylabel('Bytes');
title('Video File Sizes by Container/Codec');
grid on;
saveas(f3, fullfile(outputDir, 'plot_video_sizes.png'));

f4 = figure('Name', 'Video Difference Ratio');
bar(categorical(videoMetrics.VideoFile), videoMetrics.DifferentPixelRatioPct_Avg);
ylabel('Average Different Pixel Ratio [%]');
title(sprintf('Video Frame Difference vs %s', refName));
grid on;
saveas(f4, fullfile(outputDir, 'plot_video_diff_ratio.png'));

fprintf('\nDone. CSV and plots saved to: %s\n', outputDir);
