import ballerina/io;
import ballerina/system;
import ballerina/http;
import ballerina/config;
import wso2/azureblob;
import wso2/azurequeue;
import ballerinax/kubernetes;

@kubernetes:Service {
    serviceType: "LoadBalancer",
    port: 80
}
listener http:Listener ocrslistener = new(8080);

azureblob:Configuration blobConfig = {
    accessKey: config:getAsString("STORAGE_ACCESS_KEY"),
    account: config:getAsString("STORAGE_ACCOUNT")
};

azurequeue:Configuration queueConfig = {
    accessKey: config:getAsString("STORAGE_ACCESS_KEY"),
    account: config:getAsString("STORAGE_ACCOUNT")
};

azureblob:Client blobClient = new(blobConfig);
azurequeue:Client queueClient = new(queueConfig);

@kubernetes:Deployment {
    image: "$env{username}/ocrsxxx",
    push: true,
    username: "$env{username}",
    password: "$env{password}",
    imagePullPolicy: "Always"
}
@kubernetes:ConfigMap {
    ballerinaConf: "ballerina.conf"
}
@http:ServiceConfig {
    basePath: "/"
}
service OCRService on ocrslistener {

    @http:ResourceConfig {
        path:"/{email}"
    }
    public resource function submitOCRJob(http:Caller caller, http:Request req, string email) {
        var result = req.getBinaryPayload();
        if (result is byte[]) {
            string jobId = system:uuid();
            var pbr = blobClient->putBlob("ocrctn", jobId, result);
            if (pbr is error) {
                _ = caller->respond("Error, Reason: " + pbr.reason() + 
                                " Detail: " + <string> pbr.detail()["message"]);
            } else {
                var pmr = queueClient->putMessage("ocrqueue", jobId + ":" + email);
                if (pmr is error) {
                    _ = caller->respond("Error, Reason: " + pmr.reason() + 
                                        " Detail: " + <string> pmr.detail()["message"]);
                } 
            }
            _ = caller->respond({ job: { id: jobId }});
            io:println("JOB, ID: " + jobId, " DATA LENGTH:", result.length(), " EMAIL: ", email);
        } else {
            _ = caller->respond("Error, Reason: " + untaint result.reason() + 
                                " Detail: " + <string> untaint result.detail()["message"]);
        }
    }

}

