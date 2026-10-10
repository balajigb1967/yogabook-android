# Yoga Book YB1-91F ALSA UCM Configuration

This directory contains the ALSA Use Case Manager configuration for the RT5677 audio codec used in the Yoga Book YB1-91F.

Based on: https://github.com/Yoga-Book/Yoga-Book-ALSA-UCM-Config

## Files Expected

- `RT5677/` - Directory containing RT5677 specific configuration
  - `RT5677.conf` - Main UCM configuration file
  - `HiFi.conf` - High fidelity audio path
  - `VoiceCall.conf` - Voice call audio path
  - `Verb.conf` - Verb definitions

## Configuration Details

The RT5677 codec on Yoga Book YB1-91F requires specific verb configurations for:
- Speaker output
- Headphone output  
- Microphone input
- Voice call processing
- Echo cancellation
- Noise suppression

## Integration

This configuration is referenced in:
- `device/lenovo/yogabook/device-yogabook.mk` - BOARD_USES_ALSA_AUDIO := true
- `vendor/lenovo/yogabook/Android.mk` - Audio HAL service

To use this configuration:
1. Copy the RT5677 directory from Yoga-Book-ALSA-UCM-Config repo
2. Ensure the Audio HAL loads the UCM configuration
3. Test with `tinycap`, `tinymix`, `tinypc` utilities