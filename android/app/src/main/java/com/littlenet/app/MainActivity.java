package com.littlenet.app;

import android.Manifest;
import android.app.Activity;
import android.content.ClipData;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.provider.MediaStore;
import android.webkit.CookieManager;
import android.webkit.PermissionRequest;
import android.webkit.ValueCallback;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;
import androidx.core.content.FileProvider;
import java.io.File;
import java.util.ArrayList;
import java.util.List;

public class MainActivity extends Activity {
    private static final int FILE_CHOOSER = 42;
    private static final int RUNTIME_PERMISSIONS = 8;
    private WebView web;
    private ValueCallback<Uri[]> chooser;
    private Uri cameraUri;
    private Uri backendUri;

    private boolean sameOrigin(Uri uri) {
        if (uri == null || backendUri == null) return false;
        int p1 = uri.getPort() == -1 ? 443 : uri.getPort();
        int p2 = backendUri.getPort() == -1 ? 443 : backendUri.getPort();
        return "https".equalsIgnoreCase(uri.getScheme()) && "https".equalsIgnoreCase(backendUri.getScheme())
                && uri.getHost() != null && uri.getHost().equalsIgnoreCase(backendUri.getHost()) && p1 == p2;
    }

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        backendUri = Uri.parse(getString(R.string.backend_url));
        web = new WebView(this); setContentView(web);
        WebView.setWebContentsDebuggingEnabled(false);
        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true); s.setDomStorageEnabled(true); s.setMediaPlaybackRequiresUserGesture(false);
        s.setAllowFileAccess(false); s.setAllowContentAccess(true); s.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) s.setSafeBrowsingEnabled(true);
        CookieManager.getInstance().setAcceptCookie(true); CookieManager.getInstance().setAcceptThirdPartyCookies(web,false);

        web.setWebViewClient(new WebViewClient(){
            @Override public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request){
                Uri u=request.getUrl(); if(sameOrigin(u)) return false;
                if("https".equalsIgnoreCase(u.getScheme()) || "http".equalsIgnoreCase(u.getScheme())){
                    try{startActivity(new Intent(Intent.ACTION_VIEW,u));}catch(Exception ignored){}
                }
                return true;
            }
        });
        web.setWebChromeClient(new WebChromeClient(){
            @Override public void onPermissionRequest(PermissionRequest request){
                runOnUiThread(()->{
                    if(!sameOrigin(request.getOrigin())){request.deny();return;}
                    List<String> grant=new ArrayList<>();
                    for(String resource:request.getResources()){
                        if(PermissionRequest.RESOURCE_VIDEO_CAPTURE.equals(resource) && ContextCompat.checkSelfPermission(MainActivity.this,Manifest.permission.CAMERA)==PackageManager.PERMISSION_GRANTED) grant.add(resource);
                        if(PermissionRequest.RESOURCE_AUDIO_CAPTURE.equals(resource) && ContextCompat.checkSelfPermission(MainActivity.this,Manifest.permission.RECORD_AUDIO)==PackageManager.PERMISSION_GRANTED) grant.add(resource);
                    }
                    if(grant.isEmpty()) request.deny(); else request.grant(grant.toArray(new String[0]));
                });
            }
            @Override public boolean onShowFileChooser(WebView view,ValueCallback<Uri[]> cb,FileChooserParams params){
                if(chooser!=null) chooser.onReceiveValue(null); chooser=cb;
                Intent pick=params.createIntent(); pick.addCategory(Intent.CATEGORY_OPENABLE);
                Intent image=new Intent(MediaStore.ACTION_IMAGE_CAPTURE);
                try{
                    File f=File.createTempFile("littlenet_",".jpg",getCacheDir());
                    cameraUri=FileProvider.getUriForFile(MainActivity.this,getPackageName()+".provider",f);
                    image.putExtra(MediaStore.EXTRA_OUTPUT,cameraUri); image.addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION|Intent.FLAG_GRANT_READ_URI_PERMISSION);
                }catch(Exception e){cameraUri=null;}
                Intent video=new Intent(MediaStore.ACTION_VIDEO_CAPTURE);
                Intent audio=new Intent(MediaStore.Audio.Media.RECORD_SOUND_ACTION);
                ArrayList<Intent> extras=new ArrayList<>();
                if(image.resolveActivity(getPackageManager())!=null) extras.add(image);
                if(video.resolveActivity(getPackageManager())!=null) extras.add(video);
                if(audio.resolveActivity(getPackageManager())!=null) extras.add(audio);
                Intent chooserIntent=Intent.createChooser(pick,"Choose LittleNet media");
                chooserIntent.putExtra(Intent.EXTRA_INITIAL_INTENTS,extras.toArray(new Intent[0]));
                startActivityForResult(chooserIntent,FILE_CHOOSER); return true;
            }
        });
        ActivityCompat.requestPermissions(this,new String[]{Manifest.permission.CAMERA,Manifest.permission.RECORD_AUDIO},RUNTIME_PERMISSIONS);
        web.loadUrl(backendUri.toString());
    }

    @Override protected void onActivityResult(int requestCode,int resultCode,Intent data){
        super.onActivityResult(requestCode,resultCode,data); if(requestCode!=FILE_CHOOSER||chooser==null)return;
        Uri[] out=null;
        if(resultCode==RESULT_OK){
            if(data!=null && data.getClipData()!=null){ClipData c=data.getClipData();out=new Uri[c.getItemCount()];for(int i=0;i<c.getItemCount();i++)out[i]=c.getItemAt(i).getUri();}
            else if(data!=null && data.getData()!=null) out=new Uri[]{data.getData()};
            else if(cameraUri!=null) out=new Uri[]{cameraUri};
        }
        chooser.onReceiveValue(out);chooser=null;cameraUri=null;
    }

    @Override public void onBackPressed(){if(web!=null&&web.canGoBack())web.goBack();else super.onBackPressed();}
    @Override protected void onDestroy(){if(web!=null){web.stopLoading();web.destroy();}super.onDestroy();}
}
