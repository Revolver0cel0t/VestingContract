export const waitForSeconds = async (seconds:number) => {
    return new Promise((resolve,reject)=>{
        setTimeout(()=>{
            resolve("Done");
        },seconds * 1000)
    })
}